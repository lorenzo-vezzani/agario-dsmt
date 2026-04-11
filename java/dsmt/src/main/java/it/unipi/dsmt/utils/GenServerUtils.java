package it.unipi.dsmt.utils;

import com.ericsson.otp.erlang.*;
import it.unipi.dsmt.service.ErlangSupervisorConnectionService;
import org.jetbrains.annotations.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.util.Pair;

public class GenServerUtils {
    private static final Logger logger = LoggerFactory.getLogger(ErlangSupervisorConnectionService.class);

    /**
     * Builds a request ready to send for a gen_server (handle_call compatible)
     * @param currentNode sender's node
     * @param currentMbox sender's mbox
     * @param body request's body
     * @return message ready to send
     */
    public static OtpErlangTuple buildGenServerCallRequest(OtpNode currentNode, OtpMbox currentMbox, OtpErlangTuple body) {
        // Ref
        OtpErlangRef ref = currentNode.createRef();

        // {FromPid, Ref}
        OtpErlangTuple from = new OtpErlangTuple(new OtpErlangObject[] {
                currentMbox.self(),
                ref
        });

        // {'$gen_call', {FromPid, Ref}, body}
        OtpErlangObject[] msgArr = new OtpErlangObject[] {
                new OtpErlangAtom("$gen_call"),
                from,
                body
        };

        return new OtpErlangTuple(msgArr);
    }

    /**
     * Builds the response to send to a gen_server:call
     * @param remote reference of the node who sent the request
     * @param response body of the response
     * @return message ready to send
     */
    public static OtpErlangTuple buildGenServerCallResponse(OtpErlangObject remote, OtpErlangTuple response) {
        return new OtpErlangTuple(new OtpErlangObject[] {
                remote,
                response
        });
    }

    /**
     * Extracts the node reference (so that can be used for the response) and the body from a gen_server:call request
     * @param request received request
     * @return content of the request
     */
    public static Pair<@NotNull OtpErlangObject, @NotNull OtpErlangTuple> extractGenServerRequest(OtpErlangTuple request) {
        if (request.arity() != 3) {
            logger.error("Incorrect number of arguments for gen_server_request: {}", request);
            return null;
        }

        OtpErlangObject type =  request.elementAt(0);
        OtpErlangObject refObj = request.elementAt(1);
        OtpErlangObject body = request.elementAt(2);

        // check overall structure
        if (!(type instanceof OtpErlangAtom) || !(refObj instanceof OtpErlangTuple) || !(body instanceof OtpErlangTuple)) {
            logger.error("Incorrect request received: {}", request);
            return null;
        }

        OtpErlangAtom typeAtom = (OtpErlangAtom) type;
        if (!typeAtom.atomValue().equals("$gen_call")) {
            logger.error("Incorrect request type received: {}", request);
            return null;
        }

        // extract ref
        OtpErlangTuple refTuple = (OtpErlangTuple) refObj;
        if (refTuple.arity() != 2) {
            logger.error("Incorrect request source arity: {}", refObj);
            return null;
        }
        OtpErlangObject ref = refTuple.elementAt(1);

        return Pair.of(ref, (OtpErlangTuple) body);
    }

    /**
     * Extracts the content of a gen_server response
     * @param response what the gen_server responded
     * @return content of the response
     */
    public static OtpErlangTuple extractGenServerResponse(OtpErlangTuple response) {
        if (response.arity() != 2) {
            logger.error("Incorrect number of arguments for gen_server_response: {}", response);
            return null;
        }

        OtpErlangObject ref = response.elementAt(0);
        OtpErlangObject body = response.elementAt(1);

        if (!(body instanceof OtpErlangTuple)) {
            logger.error("Incorrect response received: {}", body);
            return null;
        }
        return (OtpErlangTuple) body;
    }
}
