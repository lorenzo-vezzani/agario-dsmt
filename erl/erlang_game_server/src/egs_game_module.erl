%%% ---------------
%%% Module description
%%%
%%% Game logic used by Game processes, one for each game
%%% Spawned and supervised by egs_supervisor
%%%
%%% State:
%%%   game_id   - binary, the unique identifier of this game session
%%%   balls     - map of PlayerId (binary) -> Ball entity (x, y, dx, dy, radius)
%%%   clients   - map of WsPid (pid) -> PlayerId (binary)
%%%
%%% The process registers itself in egs_supervisor ETS table on init
%%% and unregisters on terminate, so it can always be found by game_id.
%%% ---------------

-module(egs_game_module).
-behaviour(gen_server).

-export([start_link/1]).
-export([join/2, leave/2, player_msg/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).


% Client update refresh rate
-define(TICK_MS, 20).
% Food update refresh rate
-define(FOOD_UPDATE_TICK_MS, 1000).

-define(MAX_FOOD_COUNT, 100).

-define(STATE_FOOD, foods).


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

    % Initializes tick update
    erlang:send_after(?TICK_MS, self(), tick),
    erlang:send_after(?FOOD_UPDATE_TICK_MS, self(), food),

    % initializes state
    {ok, #{
        game_id => GameId,  % init to the passed GameId
        clients => #{},     % no clients yet
        balls   => #{},     % balls empty
        ?STATE_FOOD => egs_game_module_utils:gl__spawn_random_food_map(20) % food to eat
    }}.


%%% Called when the game process is shutting down (normally or after a crash).
%%% Removes this game from the ETS registry so no new clients can join
%%% and stale entries are not left behind.
terminate(_Reason, State) ->
    print_cli("{terminate/2} game=~s shutting down", [maps:get(game_id, State)]),
    egs_supervisor:unregister_game(maps:get(game_id, State)),
    ok.


%%% endregion 
%%% ---------------------------
%%% region JOIN/LEAVE a game
%%% ---------------------------

%%% Register the websocket handler (created upon connection by client)
%%% as a new player in the game GameId
%%% Via cast message, send the join information to the correct Game Process
join(GameId, PlayerId) ->
    print_cli("{join/2} game=~s player=~s", [GameId, PlayerId]),

    % lookup game by its id
    case egs_supervisor:lookup(GameId) of

        % game found, we can register ws handler
        {ok, Pid} ->
            % send message JOIN to game process of pid Pid
            gen_server:cast(Pid, {join, self(), PlayerId}),
            print_cli("{join/2} found game pid=~p, sending cast", [Pid]);

        % error in lookup
        Err ->
            print_cli("{join/2} lookup failed: ~p", [Err]),
            Err
    end.


%%% Unregisters a websocket handler process from the game
%%% Called by websocket handler terminate/3 when browser disconnects
%%%
%%% GameId: binary game identifier
%%% PlayerId: binary player name
leave(GameId, PlayerId) ->
    print_cli("{leave/2} game=~s player=~s", [GameId, PlayerId]),

    % search for the specified game
    case egs_supervisor:lookup(GameId) of

        % cast 'leave' message
        {ok, Pid} -> gen_server:cast(Pid, {leave, self(), PlayerId});

        Err       -> Err
    end.


%%% endregion 
%%% ---------------------------
%%% region HANDLE CAST
%%% handle messages from client
%%% ---------------------------

%%% Handles a player joining the game.
%%% - Initilizes a new ball for the playey
%%% - Also start monitoring websocket handler pid
handle_cast({join, WsPid, PlayerId}, State) ->

    % Monitor the websocket handler process. 
    % This allows autuomatic removal, via the handler DOWN
    monitor(process, WsPid),

    % spawns ball at random position with zero direction
    NewBall = egs_game_module_utils:gl__spawn_random_ball(),

    % insert new player, both to WS pids and balls map
    Clients = maps:put(WsPid, PlayerId, maps:get(clients, State)),
    Balls = maps:put(PlayerId, NewBall, maps:get(balls, State)),
    
    % log
    print_cli("{handle_cast join} player=~s (#clients=~p)", [PlayerId, maps:size(Clients)]),

    % return State
    {
        noreply, 

        % new state map
        State#{
            clients => Clients, 
            balls => Balls
        }
    };

%%% Parses and applies a raw message from the browser.
%%% All game-specific interpretation lives here, not in the WS handler.
handle_cast({player_msg, PlayerId, Msg}, State) ->

    % uncomment for full debug, every 20ms
    % print_cli("{handle_cast MSG} msg=~s", [Msg]),

    % retrive balls map
    Balls = maps:get(balls, State),

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
            {noreply, State#{balls => BallsUpdated}};

        % on whatever error just do not update
        _ ->
            {noreply, State}
    end;


%%% Handles a player leaving the game cleanly (browser tab closed normally).
%%% Removes the player from both maps.
handle_cast({leave, WsPid, PlayerId}, State) ->

    % remove from both maps
    Clients = maps:remove(WsPid, maps:get(clients, State)),
    Balls = maps:remove(PlayerId, maps:get(balls, State)),

    % log
    print_cli("{handle_cast leave} player=~s", [PlayerId]),
    
    % update state
    {noreply, State#{clients => Clients, balls => Balls}}.


%%% Send a raw browser message to the game process
%%% Parsing of message is inside handle_cast, this is 
%%% just a wrapper to avoid sending to non-existing pid
player_msg(GameId, PlayerId, Msg) ->

    % lookup pid of the game process
    case egs_supervisor:lookup(GameId) of

        % if found, send the raw message to the game process
        {ok, Pid} -> gen_server:cast(Pid, {player_msg, PlayerId, Msg});

        % not found
        Err       -> Err
    end.


%%% endregion 
%%% ---------------------------
%%% region HANDLE INFO
%%% 
%%% handles messages from other Erlang processes
%%%  - tick : from self(), to implement periodic update
%%%  - down : from websocket handler on disconnection
%%% ---------------------------

%%% Handles the periodic tick:
%%% 1) Move all balls
%%% 2) check for collisions
%%% final) Broadcast updated state to all clients
handle_info(tick, State) ->
    BallsInitial = maps:get(balls, State),
    Clients = maps:get(clients, State),
    Food = maps:get(?STATE_FOOD, State),

    % 1) move all balls
    BallsMoved = egs_game_module_utils:gl__move_balls(BallsInitial),

    % 2) collisions
    BallsAfterColl = egs_game_module_utils:gl__handle_balls_collisions(BallsMoved),

    % 3) eat food
    {BallsAfterEating, FoodAfterEating} = egs_game_module_utils:gl__eat_food(BallsAfterColl, Food),

    % finally) Broadcast
    case maps:size(Clients) of
        0 -> ok;
        _ ->
            Payload = egs_game_module_utils:encode__state(BallsAfterEating, FoodAfterEating),
            broadcast(maps:keys(Clients), Payload)
    end,

    % reschedule state update and boradcast after TICK time
    erlang:send_after(?TICK_MS, self(), tick),

    % save state
    {noreply, State#{
        balls => BallsAfterEating,
        ?STATE_FOOD => FoodAfterEating
    }};

%%% Implements periodic food spawning
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

    % Get all clients state (map of WS_pid <-> PlayerId)
    Clients = maps:get(clients, State),

    % find the player_id linked to this websocket
    case maps:find(WsPid, Clients) of

        % on player found
        {ok, PlayerId} ->
            % remove from both maps
            NewClients = maps:remove(WsPid, Clients),
            Balls = maps:remove(PlayerId, maps:get(balls, State)),

            % update state
            {noreply, State#{clients => NewClients, balls => Balls}};

        % on whatever error, keep the state
        error ->
            {noreply, State}
    end.


%%% Catch-all for unexpected synchronous calls.
%%% Returns ok without modifying state.
handle_call(_Req, _From, State) ->
    {reply, ok, State}.


%%% Sends the payload to all connected WS handler pids.
broadcast(Pids, Payload) ->
    lists:foreach(fun(Pid) ->
        Pid ! {game_state, Payload}
    end, Pids).

%%% endregion