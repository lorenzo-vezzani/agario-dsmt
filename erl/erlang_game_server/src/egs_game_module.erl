%%% ---------------
%%% Module description
%%%
%%% Game logic used by Game processes, one for each game
%%% Spawned and supervised by egs_supervisor
%%%
%%% State:
%%%   game_id   - binary, the unique identifier of this game session
%%%   clients   - map of PlayerId (binary) -> {WsPid (pid), Token supervisor, token client} 
%%%   balls     - map of PlayerId (binary) -> Ball entity (x, y, dx, dy, radius)
%%%   food      - map of FoodId -> Food entity (x, y, value)
%%%   stats     - map of PlayerId (binary) -> {stats map (deaths, kills)} 
%%%
%%% The process registers itself in egs_supervisor ETS table on init
%%% and unregisters on terminate, so it can always be found by game_id.
%%% ---------------

-module(egs_game_module).
-behaviour(gen_server).

-export([start_link/1]).
-export([
    token_auth_client/3, 
    token_auth_supervisor/3, 
    player_ask_auth/3,
    player_join/2, 
    player_input/3, 
    player_rejoin/2, 
    player_leave/2
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).


% Client update refresh rate
-define(TICK_MS, 50).

% game time, measured int seconds, then converted into tick units (div for integer division)
-define(GAME_TIME_S, 60).
-define(GAME_TIME_TICKS, ?GAME_TIME_S * 1000 div ?TICK_MS).

% Food update refresh rate
-define(FOOD_UPDATE_TICK_MS, 1000).

-define(MAX_FOOD_COUNT, 100).

-define(MAX_PLAYERS, 10).

% state variable names
-define(STATE_CLIENTS, clients).
-define(STATE_STATS, stats).
-define(STATE_BALL, balls).
-define(STATE_FOOD, foods).
-define(STATE_TIME, ticks).
-define(IS_BALL_UPDATING, is_ball_updating).
-define(IS_FOOD_UPDATING, is_food_updating).

-define(TOKEN_TYPE_SUP, token_sup).
-define(TOKEN_TYPE_CLI, token_cli).

-define(CENTRAL_SUPERVISOR_NAME, 'nodes_supervisor@10.2.1.11').

%%% ---------------------------
%%% region MANAGEMENT FUNCTIONS
%%% ---------------------------

%%% Module specific cli print
print_cli(Text, Args) -> egs_utils:print_cli("GameLogic", Text, Args).


%%% Starts a game process and links it to the calling supervisor.
%%% Called by egs_supervisor via supervisor:start_child/2.
%%%
%%% GameId - binary identifier for this game session, e.g. <<"game-1">>
%%%
%%% Returns {ok, Pid} on success.
start_link(GameId) ->
    gen_server:start_link(?MODULE, GameId, []).


%%% Initializes the game process state.
%%% Registers this pid in the ETS registry so it can be found by game_id.
%%% Schedules the first tick immediately.
%%%
%%% GameId: passed from start_link/1 via the supervisor
init(GameId) ->

    % trap_exit granys that if a linked process dies, we receive an {'EXIT', Pid, Reason} msg
    % so terminate/2 is always called for proper ETS cleanup
    process_flag(trap_exit, true),

    print_cli("{init/1} starting game=~s", [GameId]),

    % register game, for ETS table
    egs_supervisor:register_game(GameId, self()),
 
    % food to eat, 20 initial pieces
    InitialFood = egs_game_module_utils:gl__spawn_random_food_map(20),

    % initializes state
    {ok, #{
        game_id => GameId, % init to the passed GameId
        ?STATE_CLIENTS => #{}, % no clients yet
        ?STATE_STATS => #{}, % no clients yet
        ?STATE_BALL => #{}, % balls empty
        ?STATE_FOOD => InitialFood,
        ?STATE_TIME => 0,
        ?IS_BALL_UPDATING => false,
        ?IS_FOOD_UPDATING => false
    }}.


%%% Called when the game process is shutting down (normally or after a crash)
terminate(_Reason, State) ->
    print_cli("{terminate/2} game=~s shutting down", [maps:get(game_id, State)]),

    % close webosockets
    lists:foreach(
        fun(ClientMap) ->
            % send gameover only to those fully connected
            case maps:find(ws_pid, ClientMap) of
                {ok, Pid} -> Pid ! {close, 1000, <<"gameover">>};
                error -> ok
            end
        end,
        maps:values(maps:get(?STATE_CLIENTS, State))
    ),

    GameId = maps:get(game_id, State),

    Stats = maps:get(?STATE_STATS, State),
    Balls = maps:get(?STATE_BALL, State),
    Payload = egs_game_module_utils:encode__gameover(Stats, Balls),
    
    % Notify the remote central supervisor
    gen_server:cast(
        {nodes_supervisor, ?CENTRAL_SUPERVISOR_NAME}, 
        {game_terminated, GameId, Payload}
    ),

    % notify the local supervisor
    egs_supervisor:unregister_game(GameId),

    ok.


%%% endregion
%%% ---------------------------
%%% region HANDLE CAST
%%% handle messages from client
%%% ---------------------------

%%% Called upon receival of ANY token AND after the auth request
%%% Completes the authentication if all is present and token are ok
%%% Code is separated in order to be able to call this from multiple casts
complete_auth(PlayerId, ClientMap, State) ->
    
    TokenSupPresent = maps:is_key(?TOKEN_TYPE_SUP, ClientMap),
    TokenCliPresent = maps:is_key(?TOKEN_TYPE_CLI, ClientMap),
    AuthRequested = maps:is_key(ws_pid, ClientMap),

    case {TokenSupPresent, TokenCliPresent, AuthRequested} of

        % Both tokens and auth requested: we can perform auth
        {true, true, true} ->
            TokenSup = maps:get(?TOKEN_TYPE_SUP, ClientMap),
            TokenCli = maps:get(?TOKEN_TYPE_CLI, ClientMap),
            WsPid = maps:get(ws_pid, ClientMap),

            % just compare the two tokens
            {AuthResult, NewClient} = case TokenSup =:= TokenCli of

                % if tokens are equal, return ok and mark the client as authenticated
                true ->
                    print_cli("{complete_auth} player=~s OK", [PlayerId]),
                    {ok, ClientMap#{auth => ok}};

                % otherwise, return error token mismatch
                false ->
                    print_cli("{complete_auth} player=~s token_mismatch", [PlayerId]),
                    {{error, token_mismatch}, ClientMap}

            end,

            % Send result to WebSocket handler 
            WsPid ! {auth, AuthResult},

            % add the new client to the map
            % note tha upon error nothing is changed
            NewClients = maps:put(PlayerId, NewClient, maps:get(?STATE_CLIENTS, State)),
            {noreply, State#{?STATE_CLIENTS => NewClients}};

        % Not enough data (es token missing), just keep state
        _ ->
            {noreply, State}
    end.


% Just a helper function for handle_cast join
% separated to avoid nesting all of the code into the case true
perform_join(PlayerId, State) ->

    %%% 1) Check if this is the first player, handle it

    FirstPlayer = case maps:size(maps:get(?STATE_BALL, State)) of
        0 -> true;
        _ -> false
    end,

    case FirstPlayer of
        true ->
            print_cli("{handle_cast join} first client joined (~s)", [PlayerId]),

            % check if balls are updating
            case maps:get(?IS_BALL_UPDATING, State) of
                false ->
                    erlang:send_after(?TICK_MS, self(), tick),
                    print_cli("{handle_cast join} Start updating balls", []);
                true -> ok
            end,

            % check if food is updating
            case maps:get(?IS_FOOD_UPDATING, State) of
                false ->
                    erlang:send_after(?FOOD_UPDATE_TICK_MS, self(), food),
                    print_cli("{handle_cast join} Start updating food", []);
                true -> ok
            end;

        false -> ok
    end,

    %%% 2) Add the new player with Ball and Stats

    % spawns ball at random position with zero direction
    NewBall = egs_game_module_utils:gl__spawn_random_ball(),
    Balls = maps:put(PlayerId, NewBall, maps:get(?STATE_BALL, State)),

    % put a new entry in map ONLY if there's not already one (there may be if player is rejoining after closing the socket)
    Stats = case maps:is_key(PlayerId, maps:get(?STATE_STATS, State)) of

        % key not found, so insert initial stats
        false ->
            % Initial stats
            StatsInitial = #{kills => 0, deaths => 0},
            maps:put(PlayerId, StatsInitial, maps:get(?STATE_STATS, State));

        % already present, just fetch old state
        true ->
            maps:get(?STATE_STATS, State)
    end,

    %%% 3) Inform the central supervisor of the completed join
    gen_server:cast(
        {nodes_supervisor, ?CENTRAL_SUPERVISOR_NAME}, 
        {join_completed, maps:get(game_id, State)}
    ),

    % return State
    {
        noreply,

        % new state map
        State#{
            ?STATE_STATS => Stats,
            ?STATE_BALL => Balls,
            ?IS_BALL_UPDATING => true,
            ?IS_FOOD_UPDATING => true
        }
    }.


handle_cast({token, PlayerId, Token, TokenSource}, State)
        when    TokenSource =:= ?TOKEN_TYPE_CLI ;
                TokenSource =:= ?TOKEN_TYPE_SUP ->

    CurrentClients = maps:get(?STATE_CLIENTS, State),

    % construct new client
    NewClient = case maps:find(PlayerId, CurrentClients) of

        % if found, then update the client map with this token
        {ok, ExistingClient} ->
            print_cli("{token} player=~s (~s second)", [PlayerId, TokenSource]),
            ExistingClient#{TokenSource => Token};

        % if NOT found, then create the client map with only this token
        error ->
            print_cli("{token} player=~s (~s first)", [PlayerId, TokenSource]),
            #{TokenSource => Token}

    end,

    % update the state
    NewClients = maps:put(PlayerId, NewClient, CurrentClients),
    NewState = State#{?STATE_CLIENTS => NewClients},

    % Try to complete the authentication
    complete_auth(PlayerId, NewClient, NewState);

% handle cast token when Source is wrong
handle_cast({token, PlayerId, _Token, TokenSource}, State) ->
    print_cli("{token} player=~s wrong token source ~p", [PlayerId, TokenSource]),
    {noreply, State};

%%% Handles request for authentication by the client
%%% Also start monitoring websocket handler
handle_cast({auth, PlayerId, WsPid}, State) ->
    CurrentClients = maps:get(?STATE_CLIENTS, State),

    % Monitor the websocket handler process.
    % This allows autuomatic removal, via the handler DOWN
    monitor(process, WsPid),

    % adds the request to the client map
    AskingClient = case maps:find(PlayerId, CurrentClients) of
        {ok, Existing} -> Existing#{ws_pid => WsPid};
        error -> #{ws_pid => WsPid}
    end,

    % update the state
    NewClients = maps:put(PlayerId, AskingClient, CurrentClients),
    NewState = State#{?STATE_CLIENTS => NewClients},
    
    % Try to complete the authentication
    complete_auth(PlayerId, AskingClient, NewState);


%%% Handles a player joining the game.
%%% - Checks that player is already authenticated
%%% - Handles the initialization of time and food if first player
%%% - Initilizes a new ball for the player
handle_cast({join, PlayerId}, State) ->

    %%% 0) Check that joining client is authenticated

    CurrentClients = maps:get(?STATE_CLIENTS, State),

    % check that client map is present
    case maps:find(PlayerId, CurrentClients) of
        
        % if client map is present
        {ok, JoiningClient} ->
            
            % Check that auth is present
            case maps:is_key(auth, JoiningClient) of

                true ->
                    print_cli("{handle_cast join} player=~s", [PlayerId]),

                    ClientsCount = map_size(CurrentClients),
                    case ClientsCount =< ?MAX_PLAYERS of
                        % limit not reached yet
                        true -> 
                            print_cli("{handle_cast join} Number of players now = ~p", [ClientsCount]),
                            perform_join(PlayerId, State);

                        % if too many players just keep state
                        false ->
                            print_cli("{handle_cast join} Maximum number of players reached (~p)", [ClientsCount]),
                            {noreply, State}
                    end;

                % if not just keep state
                false -> 
                    print_cli("{handle_cast join} player=~s not authenticated", [PlayerId]),
                    {noreply, State}
            end;

        error ->
            print_cli("{handle_cast join} player=~s not found", [PlayerId]),
            {noreply, State}
    end;

%%% Handles a player re-joining the game after being killed.
%%% Chekcs that the socket and stats already exists AND
%%% that the ball doesn't exists
%%% - Initilizes a new ball for the player
handle_cast({rejoin, PlayerId}, State) ->

    StatePresent = maps:is_key(PlayerId, maps:get(?STATE_STATS, State)),
    ClientPresent = maps:is_key(PlayerId, maps:get(?STATE_CLIENTS, State)),
    BallPresent = maps:is_key(PlayerId, maps:get(?STATE_BALL, State)),

    NewState = case {ClientPresent, StatePresent, BallPresent} of

        % rejoin case if only the ball is missing (has been killed)
        {true, true, false} ->

            NewBall = egs_game_module_utils:gl__spawn_random_ball(),
            NewBalls = maps:put(PlayerId, NewBall, maps:get(?STATE_BALL, State)),

            print_cli("{handle_cast rejoin} player=~s rejoined with new ball", [PlayerId]),

            State#{?STATE_BALL => NewBalls};

        % not true rejoin -> keep the state unaltered
        _ ->
            print_cli("{handle_cast rejoin} player=~s invalid rejoin", [PlayerId]),
            State
    end,

    {noreply, NewState};

%%% Parses and applies a raw message from the browser.
%%% All game-specific interpretation lives here, not in the WS handler.
handle_cast({player_input, PlayerId, Msg}, State) ->

    % uncomment for full debug, every 20ms
    % print_cli("{handle_cast MSG} msg=~s", [Msg]),

    % retrive balls map
    Balls = maps:get(?STATE_BALL, State),

    % search (and get) player's ball
    PlayerBall = maps:find(PlayerId, Balls),

    % decode client message
    MsgDecoded = egs_game_module_utils:decode__direction_update(Msg),

    % decode client message, also find the ball entity of the player
    case {PlayerBall, MsgDecoded} of

        % IF player_id is found AND decode returns ok
        {{ok, Ball}, {ok, Dx, Dy}} ->

            % update balls maps, updating this player's ball info
            BallsUpdated = Balls#{
                PlayerId => Ball#{
                    dx => Dx,
                    dy => Dy
                }
            },

            % return updated state
            {noreply, State#{?STATE_BALL => BallsUpdated}};

        % on whatever error just do not update
        _ ->
            {noreply, State}
    end;


%%% Handles a player leaving the game cleanly (browser closed)
%%% Removes the player from both maps.
handle_cast({leave, PlayerId}, State) ->

    % remove from both maps
    Clients = maps:remove(PlayerId, maps:get(?STATE_CLIENTS, State)),
    Balls = maps:remove(PlayerId, maps:get(?STATE_BALL, State)),

    % log
    print_cli("{handle_cast leave} player=~s", [PlayerId]),

    % Inform the central supervisor of the leave
    gen_server:cast(
        {nodes_supervisor, ?CENTRAL_SUPERVISOR_NAME}, 
        {leave_completed, maps:get(game_id, State)}
    ),

    %% if no clients left, we can conclude the game
    case map_size(Clients) of
        0 -> erlang:send_after(0, self(), gameover);
        _ -> ok
    end,

    % update state
    {noreply, State#{?STATE_CLIENTS => Clients, ?STATE_BALL => Balls}}.

%%% endregion
%%% ---------------------------
%%% region HANDLE CAST Wrappers
%%% Redirect messages to Game Process, given GameId
%%% ---------------------------


token_auth_client(GameId, PlayerId, Token) ->
    print_cli("{token_auth_client/3} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {token, PlayerId, Token, ?TOKEN_TYPE_CLI});
        Err -> Err
    end.

token_auth_supervisor(GameId, PlayerId, Token) ->
    print_cli("{token_auth_supervisor/3} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {token, PlayerId, Token, ?TOKEN_TYPE_SUP});
        Err -> Err
    end.

player_ask_auth(GameId, PlayerId, WsPid) ->
    print_cli("{player_ask_auth/3} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {auth, PlayerId, WsPid});
        Err -> Err
    end.

player_join(GameId, PlayerId) ->
    print_cli("{player_join/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {join, PlayerId});
        Err -> Err
    end.

player_rejoin(GameId, PlayerId) ->
    print_cli("{player_rejoin/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {rejoin, PlayerId});
        Err -> Err
    end.

%%% Send a raw browser message to the game process
%%% Parsing of message is inside handle_cast
player_input(GameId, PlayerId, Msg) ->
    print_cli("{player_input/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {player_input, PlayerId, Msg});
        Err -> Err
    end.

%%% Unregisters a websocket handler process from the game
%%% Called by websocket handler terminate/3 when browser disconnects
player_leave(GameId, PlayerId) ->
    print_cli("{player_leave/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_supervisor:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {leave, PlayerId});
        Err -> Err
    end.


%%% endregion 
%%% ---------------------------
%%% region HANDLE INFO
%%% 
%%% handles messages from other Erlang processes
%%%  - tick : from self(), to implement periodic update
%%%  - food : from self(), to implement periodic food spawn
%%%  - gameover : from self(), to implement gameover procedure
%%%  - down : from websocket handler on disconnection
%%% ---------------------------

%%% Handles the periodic tick:
%%% 1) Move all balls
%%% 2) check for collisions
%%% 3) handle all food eating
%%% final) Broadcast updated state to all clients

% avoid doing the compytation loop if no clients are present
% should never occur unless scheduled at exact time with last client leave
handle_info(tick, #{?STATE_CLIENTS := Clients} = State) when map_size(Clients) == 0 ->
    {noreply, State};

handle_info(tick, State) ->
    StartTime = erlang:monotonic_time(millisecond),

    BallsInitial = maps:get(?STATE_BALL, State),
    Clients = maps:get(?STATE_CLIENTS, State),
    Stats = maps:get(?STATE_STATS, State),
    Food = maps:get(?STATE_FOOD, State),

    % 1) move all balls
    BallsMoved = egs_game_module_utils:gl__move_balls(BallsInitial),

    % 2) collisions
    {BallsAfterColl, Collisions} = egs_game_module_utils:gl__handle_balls_collisions(BallsMoved),

    % 3) eat food
    {BallsAfterEating, FoodAfterEating} = egs_game_module_utils:gl__eat_food(BallsAfterColl, Food),

    % update kill count
    StatsUpdated = egs_game_module_utils:gl__update_stats(Stats, Collisions),

    % finally) Broadcast
    Payload = egs_game_module_utils:encode__state(BallsAfterEating, FoodAfterEating, StatsUpdated),
    broadcast(Clients, game_state, Payload),

    % schedule next update
    case maps:get(?STATE_TIME, State) < ?GAME_TIME_TICKS of
        true ->
            % reschedule state update and broadcast after TICK time - elapsed
            ElapsedMs = erlang:monotonic_time(millisecond) - StartTime,

            % Max out at 0, if elapsed > tick (maybe some big overhead)
            NextUpdate = max(0, ?TICK_MS - ElapsedMs),
            erlang:send_after(NextUpdate, self(), tick);

        false ->
            % don't schedule update, schedule end of game
            erlang:send_after(0, self(), gameover)
    end,

    % save state
    {noreply, State#{
        ?STATE_STATS => StatsUpdated,
        ?STATE_BALL => BallsAfterEating,
        ?STATE_FOOD => FoodAfterEating,
        ?STATE_TIME => (maps:get(?STATE_TIME, State) + 1)
    }};


%%% Implements periodic food spawning
handle_info(food, #{?STATE_CLIENTS := Clients} = State) when map_size(Clients) == 0 ->
    {noreply, State};

handle_info(food, State) ->

    % reschedule food update
    erlang:send_after(?FOOD_UPDATE_TICK_MS, self(), food),

    FoodMap = maps:get(?STATE_FOOD, State),

    case maps:size(FoodMap) < ?MAX_FOOD_COUNT of
        true ->
            % insert new food in map
            {FoodId, FoodElem} = egs_game_module_utils:gl__spawn_random_food(),
            FoodUpdated = maps:put(FoodId, FoodElem, FoodMap),

            % save state
            {noreply, State#{
                ?STATE_FOOD => FoodUpdated
            }};

        false ->
            % do not change state
            {noreply, State}
    end;

handle_info(gameover, State) ->
    Clients = maps:get(?STATE_CLIENTS, State),
    Stats = maps:get(?STATE_STATS, State),
    Balls = maps:get(?STATE_BALL, State),
    Payload = egs_game_module_utils:encode__gameover(Stats, Balls),

    % broadcast the ending state and information
    broadcast(Clients, gameover, Payload),

    {stop, normal, State};

%%% Handles death of a monitored websocket handler process
%%% Triggered when a client crashes or disconnects without calling leave/2
%%% 
%%% Removes the player from both the clients and balls maps
%%% 
%%% IMPORTANT NOTE: 
%%%     this is also called on normal disconnection
%%%     in that case it also executes, just doesn't find any matches
%%%     they have already been removed from maps
handle_info({'DOWN', _Ref, process, WsPid, Reason}, State) ->
    print_cli("{handle_info DOWN} ws_pid=~p reason=~p", [WsPid, Reason]),

    % Get all clients state (map of PlayerId <-> WS_pid)
    Clients = maps:get(?STATE_CLIENTS, State),

    % need to find player_id by ws_pid
    Players = [PlayerId || {PlayerId, #{ws_pid := Pid}} <- maps:to_list(Clients), Pid =:= WsPid],

    % find the player_id linked to this websocket
    case Players of

        % one player found
        [PlayerId] ->
            % remove from both maps
            NewClients = maps:remove(PlayerId, Clients),
            Balls = maps:remove(PlayerId, maps:get(?STATE_BALL, State)),

            % update state
            {noreply, State#{?STATE_CLIENTS => NewClients, ?STATE_BALL => Balls}};

        % More than one player found, keep the state
        % this should never happen
        [_|_] -> {noreply, State};

        % No player found, keep the state
        [] -> {noreply, State}
    end.


%%% Catch-all for unexpected synchronous calls.
%%% Returns ok without modifying state.
handle_call(_Req, _From, State) ->
    {reply, ok, State}.


%%% Sends the payload to all connected WS handler pids.
broadcast(Clients, Atom, Payload) ->

    % get websocket handlers PIDs (list)
    % ws_pid my not be present if client is in the middle of auth proces
    WsHandlerPIDs = [
        maps:get(ws_pid, ClientMap)             % get WsPid from the clientMap
        || ClientMap <- maps:values(Clients),   % ClientMap are just the single maps of Clients
        maps:is_key(ws_pid, ClientMap)          % ONLY IF ws_pid is present
    ],

    % juts send the same message to everyone
    lists:foreach(
        fun(Pid) ->
            Pid ! {Atom, Payload}
        end,
        WsHandlerPIDs
    ).

%%% endregion
