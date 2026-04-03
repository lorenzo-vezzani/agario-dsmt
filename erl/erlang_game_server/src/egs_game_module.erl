%%% ---------------
%%% Module description
%%%
%%% Game logic used by Game processes, one for each game
%%% Spawned and supervised by egs_supervisor
%%%
%%% State:
%%%   game_id   - binary, the unique identifier of this game session
%%%   balls     - map of PlayerId (binary) -> Ball entity (x, y, dx, dy, radius)
%%%   clients   - map of PlayerId (binary) -> {WsPid (pid), Client stats} 
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
-define(TICK_MS, 50).

% game time, measured int seconds, then converted into tick units (div for integer division)
-define(GAME_TIME_S, 60).
-define(GAME_TIME_TICKS, ?GAME_TIME_S * 1000 div ?TICK_MS).

% Food update refresh rate
-define(FOOD_UPDATE_TICK_MS, 1000).

-define(MAX_FOOD_COUNT, 100).

% state variable names
-define(STATE_CLIENTS, clients).
-define(STATE_STATS, stats).
-define(STATE_BALL, balls).
-define(STATE_FOOD, foods).
-define(STATE_TIME, ticks).
-define(IS_BALL_UPDATING, is_ball_updating).
-define(IS_FOOD_UPDATING, is_food_updating).


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

    % initializes state
    {ok, #{
        game_id => GameId, % init to the passed GameId
        ?STATE_CLIENTS => #{}, % no clients yet
        ?STATE_STATS => #{}, % no clients yet
        ?STATE_BALL => #{}, % balls empty
        ?STATE_FOOD => egs_game_module_utils:gl__spawn_random_food_map(20), % food to eat, 20 initial pieces
        ?STATE_TIME => 0,
        ?IS_BALL_UPDATING => false,
        ?IS_FOOD_UPDATING => false
    }}.


%%% Called when the game process is shutting down (normally or after a crash)
terminate(_Reason, State) ->
    print_cli("{terminate/2} game=~s shutting down", [maps:get(game_id, State)]),

    % close webosockets
    lists:foreach(
        fun(#{ws_pid := Pid}) -> Pid ! {close, 1000, <<"gameover">>} end,
        maps:values(maps:get(?STATE_CLIENTS, State))
    ),

    % unregitser game
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
        {ok, Pid} -> gen_server:cast(Pid, {leave, PlayerId});

        Err -> Err
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

    IsBallUpdating = maps:get(?IS_BALL_UPDATING, State),
    IsFoodUpdating = maps:get(?IS_FOOD_UPDATING, State),
    CurrentClients = maps:get(?STATE_CLIENTS, State),
    %% if this is the first client and the balls update isn't active, start updates on balls
    case {CurrentClients, IsBallUpdating} of
        {#{}, false} ->
            % Initializes tick update
            erlang:send_after(?TICK_MS, self(), tick),
            print_cli("{handle_cast join} first client joined (~s), starting updating ball", [PlayerId]);
        _ -> ok
    end,
    %% if this is the first client and the food update isn't active, start updates on food
    case {CurrentClients, IsFoodUpdating} of
        {#{}, false} ->
            % Initializes tick update
            erlang:send_after(?FOOD_UPDATE_TICK_MS, self(), food),
            print_cli("{handle_cast join} first client joined (~s), starting updating food", [PlayerId]);
        _ -> ok
    end,

    % spawns ball at random position with zero direction
    NewBall = egs_game_module_utils:gl__spawn_random_ball(),

    % initialize client state
    ClientState = #{ws_pid => WsPid},

    % insert new player
    Clients = maps:put(PlayerId, ClientState, maps:get(?STATE_CLIENTS, State)),
    Balls = maps:put(PlayerId, NewBall, maps:get(?STATE_BALL, State)),

    % put a new entry in map ONLY if there's not already one (there may be if player is rejoining)
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

    % log
    print_cli("{handle_cast join} player=~s (#clients=~p)", [PlayerId, maps:size(Clients)]),

    % return State
    {
        noreply,

        % new state map
        State#{
            ?STATE_CLIENTS => Clients,
            ?STATE_STATS => Stats,
            ?STATE_BALL => Balls,
            ?IS_BALL_UPDATING => true,
            ?IS_FOOD_UPDATING => true
        }
    };

%%% Parses and applies a raw message from the browser.
%%% All game-specific interpretation lives here, not in the WS handler.
handle_cast({player_msg, PlayerId, Msg}, State) ->

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


%%% Handles a player leaving the game cleanly (browser tab closed normally).
%%% Removes the player from both maps.
handle_cast({leave, PlayerId}, State) ->

    % remove from both maps
    Clients = maps:remove(PlayerId, maps:get(?STATE_CLIENTS, State)),
    Balls = maps:remove(PlayerId, maps:get(?STATE_BALL, State)),

    % log
    print_cli("{handle_cast leave} player=~s", [PlayerId]),

    %% if no clients left, we can conclude the game
    case map_size(Clients) of
        0 -> erlang:send_after(0, self(), gameover);
        _ -> ok
    end,

    % update state
    {noreply, State#{?STATE_CLIENTS => Clients, ?STATE_BALL => Balls}}.


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

    egs_supervisor:stop_game(maps:get('game-id', Payload)),

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
    WsHandlerPIDs = [maps:get(ws_pid, ClientMap) || ClientMap <- maps:values(Clients)],

    lists:foreach(
        fun(Pid) ->
            Pid ! {Atom, Payload}
        end,
        WsHandlerPIDs
    ).

%%% endregion