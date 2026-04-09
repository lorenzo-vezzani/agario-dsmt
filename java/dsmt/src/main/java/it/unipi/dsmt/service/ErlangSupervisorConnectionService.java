package it.unipi.dsmt.service;

import com.ericsson.otp.erlang.*;
import it.unipi.dsmt.config.AgarioConfig;
import it.unipi.dsmt.dto.GameStatsDTO;
import it.unipi.dsmt.dto.LobbyInfoDTO;
import it.unipi.dsmt.dto.PlayerStatDTO;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.task.TaskExecutor;
import org.springframework.stereotype.Service;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/*
requests:
    new_lobby_req           ->  { new_lobby_req, req_id, {} }                                  J -> E
    join_lobby_req          ->  { join_lobby_req, req_id, {"username", "token", lobby_id} }    J -> E
    stats_req               ->  { stats_req, req_id, {json_string} }                           E -> J
    get_lobbies_req         ->  { get_lobbies_req, req_id, {} }                                J -> E

responses:
    new_lobby_resp          ->  { new_lobby_resp, req_id, {result(atom), ip_addr, port, lobby_id} }                        E -> J
    join_lobby_resp         ->  { join_lobby_resp, req_id, {result(atom)} }                                                E -> J
    stats_resp              ->  { stats_resp, req_id, {result (atom)} }                                                    J -> E
    get_lobbies_resp        ->  { get_lobbies_resp, req_id, {result (atom), [{ip_addr, port, lobby_id, n_players}, ...]} } E -> J
 */
@Service
public class ErlangSupervisorConnectionService {

    /**
     * For saving player stats
     */
    @Autowired
    private UserService userService;

    /**
     * For gathering erlang configs
     */
    @Autowired
    private AgarioConfig agarioConfig;

    /**
     * For erlang listener scheduling
     */
    @Qualifier("applicationTaskExecutor")
    @Autowired
    private TaskExecutor taskExecutor;

    /**
     * For closing application if something goes wrong
     */
    @Autowired
    ConfigurableApplicationContext applicationContext;

    /**
     * For erlang listener stopping
     */
    private final AtomicBoolean running = new AtomicBoolean(true);

    /**
     * Associates request ID to the corresponding future
     */
    private final ConcurrentHashMap<Integer, CompletableFuture<OtpErlangTuple>> pendingRequests = new ConcurrentHashMap<>();

    /**
     * Stores the next request ID to be used
     */
    private final AtomicInteger nextRequestId = new AtomicInteger(0);

    private OtpNode currentNode;
    private OtpMbox currentMbox;

    private static final Logger logger = LoggerFactory.getLogger(ErlangSupervisorConnectionService.class);

    /**
     * Starts the task that will receive messages from the erlang supervisor
     */
    @PostConstruct
    public void startSupervisorConnection() {
        logger.info("Starting Erlang Supervisor Connection Service");
        if(!connect()) {
            applicationContext.close();
            return;
        }
        logger.info("Supervisor set at {}", agarioConfig.getSupervisorNodeName() + "@" + agarioConfig.getSupervisorIp());

        // listener process
        taskExecutor.execute(() -> {
            logger.info("Supervisor listener started at {}!", currentNode.node());
            while (running.get()) {
                try {
                    OtpErlangObject msg = currentMbox.receive(100);
                    if (msg == null) {
                        continue;
                    }
                    System.out.println(msg);
                    try {
                        processMessage(msg);
                    }
                    catch (ClassCastException e) {
                        logger.error("Invalid message format received: " + e.getMessage());
                    }
                    catch (NullPointerException e) {
                        logger.error("Error trying to parse message: " + e.getMessage());
                    }
                }
                catch (OtpErlangRangeException e) {
                    logger.warn("Integer range error: {}", e.getMessage());
                    nextRequestId.set(0);
                } catch (OtpErlangExit e) {
                    // TODO ???
                    logger.error("Supervisor terminated with an error: {}", e.getMessage());
                    break;
                } catch (OtpErlangDecodeException e) {
                    throw new RuntimeException(e);
                }
            }
            logger.info("Supervisor listener stopped!");
        });
    }

    /**
     * Creates the erlang node and mailbox
     * @return if the operation is successful
     */
    private boolean connect() {
        try {
            // epmd daemon must be active, otherwise can't publish this node name
            // command: epmd -daemon
            currentNode = new OtpNode("springboot_node@" + agarioConfig.getSelfErlangIp(), agarioConfig.getSupervisorCookie());
            currentMbox = currentNode.createMbox("springboot_mbox");
            return true;
        }
        catch (IOException e) {
            logger.error("Error starting Supervisor Connection Service: {}", e.toString());
        }
        return false;
    }

    /**
     * Closes the erlang node and mailbox
     */
    private void disconnect() {
        currentMbox.close();
        currentNode.close();
    }

    /**
     * Encapsulates the request in a message that gen_server supports
     * @param request request to send to the supervisor
     * @return message ready to send
     */
    private OtpErlangTuple buildGenServerCall(OtpErlangTuple request) {
        // Ref
        OtpErlangRef ref = currentNode.createRef();

        // {FromPid, Ref}
        OtpErlangTuple from = new OtpErlangTuple(new OtpErlangObject[] {
                currentMbox.self(),
                ref
        });

        // {'$gen_call', {FromPid, Ref}, Request}
        OtpErlangObject[] msgArr = new OtpErlangObject[] {
                new OtpErlangAtom("$gen_call"),
                from,
                request
        };

        return new OtpErlangTuple(msgArr);
    }

    private OtpErlangTuple extractGenServerResponse(OtpErlangTuple response) {
        if (response.arity() != 2) {
            logger.error("Incorrect number of arguments for gen_server_response: {}", response);
            return null;
        }

        OtpErlangObject ref = response.elementAt(0);
        OtpErlangObject reply = response.elementAt(1);

        if (!(reply instanceof OtpErlangTuple)) {
            logger.error("Incorrect response received: {}", reply);
            return null;
        }
        return (OtpErlangTuple) reply;
    }

    /**
     * Sends a single message with the correct format
     * @param type type of the message
     * @param requestId request id of the message
     * @param content payload of the message
     */
    private void sendMessage(OtpErlangAtom type, int requestId, OtpErlangTuple content) {
        OtpErlangTuple msg = new OtpErlangTuple(
                new OtpErlangObject[]{
                        type,
                        new OtpErlangInt(requestId),
                        content
                }
        );
        OtpErlangTuple toSend = buildGenServerCall(msg);
        currentMbox.send(agarioConfig.getSupervisorMb(), agarioConfig.getSupervisorNodeName() + "@" + agarioConfig.getSupervisorIp(), toSend);
    }

    /**
     * Processes a received message.
     * @param packet received message
     * @throws OtpErlangRangeException if the conversion from erlang integer to java integer goes wrong
     */
    private void processMessage(OtpErlangObject packet) throws OtpErlangRangeException {
        if (!(packet instanceof OtpErlangTuple)) {
            logger.error("invalid message: {}", packet);
            return;
        }

        OtpErlangTuple tuple = extractGenServerResponse((OtpErlangTuple) packet);
        if (tuple == null) {
            return;
        }

        String type = tuple.elementAt(0).toString();
        int req_id = ((OtpErlangLong)(tuple.elementAt(1))).intValue();
        OtpErlangTuple content = (OtpErlangTuple) tuple.elementAt(2);

        // responses
        if (type.endsWith("_resp")) {
            processResponses(req_id, content);
        }
        // new stats arrived
        else if (type.equals("stats_req")) {
            processStats(req_id, content);
        }
        // unknown message received
        else {
            logger.error("Unrecognized message type: {}", tuple.toString());
        }
    }

    /**
     * Delivers responses relative to sent requests (and their futures).
     * @param req_id received request ID
     * @param content received content in the response
     */
    private void processResponses(int req_id, OtpErlangTuple content) {
        CompletableFuture<OtpErlangTuple> future = pendingRequests.get(req_id);

        if (future != null) {
            future.complete(content);
            return;
        }
        logger.warn("Response received from supervisor but no request sent");
    }

    /**
     * Saves the received statistics from the supervisor.
     * Format:
     * <pre>
     * {
     *     "type": "gameover",
     *     "ordered_balls": [
     *         {
     *             "id": "prova1",
     *             "x": 0,
     *             "y": 1060.6,
     *             "r": 20
     *         }
     *     ],
     *     "stats": [
     *         {
     *             "id": "prova1",
     *             "kills": 0,
     *             "deaths": 0
     *         }
     *     ]
     * }
     * </pre>
     * @param req_id request ID contained in the received request
     * @param content content in the received request (the stats)
     */
    private void processStats(int req_id, OtpErlangTuple content) {
        logger.info("New stats received!");

        OtpErlangString erlangJson = (OtpErlangString) content.elementAt(0);
        String jsonString = erlangJson.stringValue();
        ObjectMapper mapper = new ObjectMapper();
        GameStatsDTO stats = mapper.readValue(jsonString, GameStatsDTO.class);
        List<PlayerStatDTO> playerStats = stats.stats;

        for (PlayerStatDTO playerStat : playerStats) {
            boolean isWinner = playerStats.get(0).id.equals(playerStat.id);
            userService.updateUserStats(playerStat.id, isWinner, playerStat.kills, playerStat.deaths);
        }

        OtpErlangTuple result = new OtpErlangTuple(new OtpErlangAtom("ok"));
        sendMessage(new OtpErlangAtom("stats_resp"), req_id, result);
    }

    /**
     * blocking function that sends a request to the supervisor and waits for a response (or timeout).
     * It handles the communication aspects like request id and message format.
     * @param type erlang atom specifying the message type
     * @param content erlang tuple with the payload
     * @return tuple found in the response message (null for timeout)
     */
    private OtpErlangTuple sendRequest(OtpErlangAtom type, OtpErlangTuple content) {
        // create pending request
        CompletableFuture<OtpErlangTuple> future = new CompletableFuture<>();   // create future
        int requestId = nextRequestId.getAndIncrement();                        // extract request id to use
        pendingRequests.put(requestId, future);                                 // insert future in pending requests

        // send request
        sendMessage(type, requestId, content);

        try {
            // wait for response
            return future.get(5, TimeUnit.SECONDS);
        } catch (ExecutionException e) {
            logger.error("Error sending request to supervisor: {}", String.valueOf(e.getCause()));
            return null;
        } catch (InterruptedException e) {
            return null;
        } catch (TimeoutException e) {
            logger.error("No response from the supervisor");
            return null;
        } finally {
            pendingRequests.remove(requestId);
        }
    }

    /**
     * Called when the application is shutting down, stops the erlang listener thread
     */
    @EventListener(ContextClosedEvent.class)
    public void onShutdown() {
        logger.info("Stopping Erlang Supervisor Connection Service...");
        running.set(false);
    }

    /**
     * Called before destroying this object, closes the erlang node and mailbox
     */
    @PreDestroy
    public void stopSupervisorConnection() {
        logger.info("Destroying Erlang Supervisor Connection Service...");
        disconnect();
    }


    // ---------- FUNCTIONS FOR INTERFACING WITH THE SUPERVISOR ---------- //

    /**
     * Sends a create lobby request to the supervisor
     * @return the new lobby details, null if an error occurred
     */
    public LobbyInfoDTO sendCreateLobbyRequest() {
        OtpErlangTuple payload = new OtpErlangTuple(new OtpErlangObject[]{});
        OtpErlangTuple response = sendRequest(new OtpErlangAtom("new_lobby_req"), payload);

        if (response == null) {
            logger.error("sendCreateLobbyRequest: Error sending create lobby request to supervisor");
            return null;
        }
        OtpErlangAtom result = (OtpErlangAtom) response.elementAt(0);
        OtpErlangString ip = (OtpErlangString) response.elementAt(1);
        OtpErlangLong port = (OtpErlangLong) response.elementAt(2);
        OtpErlangString lobbyId = (OtpErlangString) response.elementAt(3);

        if (!result.toString().equals("ok")) {
            // TODO HANDLE ERROR CASES
            logger.error("sendCreateLobbyRequest: Supervisor returned error code after create lobby request");
            return null;
        }

        int intPort;
        try {
            intPort = port.intValue();
        } catch (OtpErlangRangeException e) {
            logger.error("sendCreateLobbyRequest: Error converting port to int {}", e.getMessage());
            return null;
        }

        return new LobbyInfoDTO(ip.stringValue(), intPort, lobbyId.stringValue(), 0);
    }

    /**
     * Grants access to an existing lobby by sending the request to the supervisor
     * @param username client's username
     * @param lobbyId lobby id of the game that the client wants authorization
     * @param token client's token
     * @return if the request is successful
     */
    public boolean sendJoinLobbyRequest(String username, String lobbyId, String token) {
        OtpErlangTuple payload = new OtpErlangTuple(new OtpErlangObject[]{
                new OtpErlangString(username),
                new OtpErlangString(lobbyId),
                new OtpErlangString(token)
        });
        OtpErlangTuple response = sendRequest(new OtpErlangAtom("join_lobby_req"), payload);

        if (response == null) {
            logger.error("sendJoinLobbyRequest: Error sending join lobby request to supervisor");
            return false;
        }
        OtpErlangAtom result = (OtpErlangAtom) response.elementAt(0);

        if (!result.toString().equals("ok")) {
            // TODO HANDLE ERROR CASES
            logger.error("sendJoinLobbyRequest: Supervisor returned error code after join lobby request");
            return false;
        }

        return true;
    }

    public List<LobbyInfoDTO> sendListLobbyRequest() {
        OtpErlangTuple payload = new OtpErlangTuple(new OtpErlangObject[]{});
        OtpErlangTuple response = sendRequest(new OtpErlangAtom("get_lobbies_req"), payload);

        if  (response == null) {
            logger.error("sendListLobbyRequest: Error sending get lobbies request to supervisor");
            return null;
        }
        OtpErlangAtom result = (OtpErlangAtom) response.elementAt(0);
        OtpErlangList lobbies = (OtpErlangList) response.elementAt(1);

        if (!result.toString().equals("ok")) {
            // TODO HANDLE ERROR CASES
            logger.error("sendListLobbyRequest: Supervisor returned error code after get lobbies request");
            return null;
        }

        // build lobby list
        List<LobbyInfoDTO> lobbiesList = new ArrayList<>();
        for (int i = 0; i < lobbies.arity(); i++) {
            OtpErlangTuple lobby = (OtpErlangTuple) lobbies.elementAt(i);
            OtpErlangString lobbyIp = (OtpErlangString) lobby.elementAt(0);
            OtpErlangLong lobbyPort = (OtpErlangLong) lobby.elementAt(1);
            OtpErlangString lobbyId = (OtpErlangString) lobby.elementAt(2);
            OtpErlangLong lobbyPlayers = (OtpErlangLong) lobby.elementAt(3);

            try {
                lobbiesList.add(new LobbyInfoDTO(lobbyIp.stringValue(), lobbyPort.intValue(), lobbyId.stringValue(), lobbyPlayers.intValue()));
            } catch (OtpErlangRangeException e) {
                logger.error("sendListLobbyRequest: Error converting port to int {}", e.getMessage());
                return null;
            }
        }
        return lobbiesList;
    }
}