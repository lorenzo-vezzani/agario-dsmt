%%% ---------------
%%% Module description
%%%
%%% Game logic process — one instance per running game session.
%%% Implemented as a gen_server. Spawned and supervised by egs_games_mgmt.
%%%
%%% Responsibilities:
%%%   - track which WebSocket handler processes are connected (clients map)
%%%   - track each player's game actions
%%%   - broadcast the current counters to all clients every TICK_MS milliseconds
%%%   - handle player join, leave, and action events
%%%   - monitor connected WS handler pids and clean up if one crashes
%%%
%%% State:
%%%   game_id  - binary, the unique identifier of this game session
%%%   counters - map of PlayerId (binary) -> press count (integer) TODO CHANGE
%%%   clients  - map of WsPid (pid) -> PlayerId (binary)
%%%
%%% The process registers itself in egs_games_mgmt's ETS table on init
%%% and unregisters on terminate, so it can always be found by game_id.
%%% ---------------

-module(egs_game_module).
-behaviour(gen_server).

-export([start_link/1]).
-export([join/2, leave/2, set_direction/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).


% Client update refresh rate
-define(TICK_MS, 20).
-define(ARENA_W,    2000.0).
-define(ARENA_H,    2000.0).
-define(BALL_R,     20.0).
-define(SPEED,      3.0).


%%% Module specific cli print
print_cli(Text, Args) ->
    io:format("[GameLogic][~p] " ++ Text ++ "~n", [self()] ++ Args).


%%% Starts a game process and links it to the calling supervisor.
%%% Called by egs_games_mgmt via supervisor:start_child/2.
%%%
%%% GameId - binary identifier for this game session, e.g. <<"game-1">>
%%%
%%% Returns {ok, Pid} on success.
start_link(GameId) ->
    gen_server:start_link(?MODULE, GameId, []).

%%% Registers a WebSocket handler process as a player in this game.
%%% Looks up the game pid from the registry, then sends an async cast.
%%% The cast includes self() so the game process can monitor the WS handler.
%%%
%%% IMPORTANT: must be called from websocket_init/1, not init/2,
%%% so the WS process is fully initialized before being monitored.
%%%
%%% GameId   - binary game identifier
%%% PlayerId - binary player name, e.g. <<"alice">>
join(GameId, PlayerId) ->
    print_cli("{join/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_games_mgmt:lookup(GameId) of
        {ok, Pid} ->
            print_cli("{join/2} found game pid=~p, sending cast", [Pid]),
            gen_server:cast(Pid, {join, self(), PlayerId});
        Err ->
            print_cli("{join/2} lookup failed: ~p", [Err]),
            Err
    end.


%%% Unregisters a WebSocket handler process from the game.
%%% Called by the WS handler's terminate/3 when the browser disconnects.
%%% The game process removes the player from both the clients and counters maps.
%%%
%%% GameId   - binary game identifier
%%% PlayerId - binary player name
leave(GameId, PlayerId) ->
    print_cli("{leave/2} game=~s player=~s", [GameId, PlayerId]),
    case egs_games_mgmt:lookup(GameId) of
        {ok, Pid} -> gen_server:cast(Pid, {leave, self(), PlayerId});
        Err       -> Err
    end.


%%% Updates the movement direction for a player's ball.
%%% Called by the WS handler every time the browser sends a mouse position.
%%%
%%% The direction vector {Dx, Dy} is expected to be already normalized
%%% (unit vector) by the client, so the server only needs to scale by speed.
%%%
%%% GameId   - binary game identifier
%%% PlayerId - binary player name
%%% {Dx, Dy} - normalized direction vector (floats in range [-1.0, 1.0])
set_direction(GameId, PlayerId, {Dx, Dy}) ->
    case egs_games_mgmt:lookup(GameId) of
        {ok, Pid} ->
            gen_server:cast(Pid, {set_direction, PlayerId, Dx, Dy});
        Err ->
            print_cli("{set_direction/3} lookup failed: ~p", [Err]),
            Err
    end.


%%% Initializes the game process state.
%%% Registers this pid in the ETS registry so it can be found by game_id.
%%% Schedules the first tick immediately.
%%%
%%% GameId - passed from start_link/1 via the supervisor
init(GameId) ->

    % TODO comment
    process_flag(trap_exit, true),
    print_cli("{init/1} starting game=~s", [GameId]),
    egs_games_mgmt:register(GameId, self()),
    erlang:send_after(?TICK_MS, self(), tick),
    {ok, #{
        game_id => GameId,
        players => #{},
        clients => #{}
    }}.


%%% Handles a player joining the game.
%%% Monitors the WS handler pid so we can clean up if it crashes unexpectedly.
%%% Initializes the player's counter to 0.
handle_cast({join, WsPid, PlayerId}, State) ->

    %% Monitor the WS handler process. If it crashes (e.g. network drop),
    %% we receive a {'DOWN', ...} message and remove the player automatically,
    %% without needing the WS handler to call leave/2 explicitly.
    monitor(process, WsPid),

    % spawns ball at random position with zero direction
    Player = #{
        x      => rand:uniform() * ?ARENA_W,
        y      => rand:uniform() * ?ARENA_H,
        dx     => 0.0,
        dy     => 0.0,
        radius => ?BALL_R
    },

    Clients = maps:put(WsPid, PlayerId, maps:get(clients, State)),
    Players = maps:put(PlayerId, Player, maps:get(players, State)),
    print_cli("{handle_cast join} player=~s clients_now=~p",
        [PlayerId, maps:size(Clients)]),
    {noreply, State#{clients => Clients, players => Players}};

%%% Handles a player leaving the game cleanly (browser tab closed normally).
%%% Removes the player from both maps.
handle_cast({leave, WsPid, PlayerId}, State) ->
    Clients = maps:remove(WsPid, maps:get(clients, State)),
    Players = maps:remove(PlayerId, maps:get(players, State)),
    print_cli("{handle_cast leave} player=~s", [PlayerId]),
    {noreply, State#{clients => Clients, players => Players}};


%%% Updates the direction vector for a player's ball.
%%% The direction is stored and applied on the next tick.
handle_cast({set_direction, PlayerId, Dx, Dy}, State) ->
    Players = maps:get(players, State),
    case maps:find(PlayerId, Players) of
        {ok, Player} ->
            NewPlayer  = Player#{dx => Dx, dy => Dy},
            NewPlayers = maps:put(PlayerId, NewPlayer, Players),
            {noreply, State#{players => NewPlayers}};
        error ->
            {noreply, State}
    end.


%%% Handles the periodic tick:
%%%   1. Move all balls according to their current direction
%%%   2. Check for collisions between all pairs of balls
%%%   3. Broadcast the updated state to all clients
handle_info(tick, State) ->
    Players0 = maps:get(players, State),
    Clients  = maps:get(clients, State),

    %% Step 1: move all balls
    Players1 = move_all(Players0),

    %% Step 2: check collisions (log only, no effect)
    check_collisions(Players1),

    %% Step 3: broadcast if there are clients
    case maps:size(Clients) of
        0 -> ok;
        _ ->
            Payload = encode_state(Players1),
            broadcast(maps:keys(Clients), Payload)
    end,

    erlang:send_after(?TICK_MS, self(), tick),
    {noreply, State#{players => Players1}};


%%% Handles the death of a monitored WS handler process.
%%% Triggered when a client crashes or disconnects without calling leave/2
%%% (e.g. network interruption, browser crash).
%%% Removes the player from both the clients and counters maps.
handle_info({'DOWN', _Ref, process, WsPid, Reason}, State) ->
    print_cli("{handle_info DOWN} ws_pid=~p reason=~p", [WsPid, Reason]),
    case maps:find(WsPid, maps:get(clients, State)) of
        {ok, PlayerId} ->
            Clients = maps:remove(WsPid, maps:get(clients, State)),
            Players = maps:remove(PlayerId, maps:get(players, State)),
            {noreply, State#{clients => Clients, players => Players}};
        error ->
            {noreply, State}
    end.


%%% Catch-all for unexpected synchronous calls.
%%% Returns ok without modifying state.
handle_call(_Req, _From, State) ->
    {reply, ok, State}.


%%% Called when the game process is shutting down (normally or after a crash).
%%% Removes this game from the ETS registry so no new clients can join
%%% and stale entries are not left behind.
terminate(_Reason, State) ->
    print_cli("{terminate/2} game=~s shutting down", [maps:get(game_id, State)]),
    egs_games_mgmt:unregister(maps:get(game_id, State)),
    ok.

%%% ---------------
%%% Internal helpers
%%% ---------------

%%% Moves every ball by (dx * SPEED, dy * SPEED), clamped to arena bounds.
%%% A ball with dx=dy=0 (just joined, no input yet) does not move.
move_all(Players) ->
    maps:map(fun(_PlayerId, Player) ->
        X  = maps:get(x,  Player),
        Y  = maps:get(y,  Player),
        Dx = maps:get(dx, Player),
        Dy = maps:get(dy, Player),
        R  = maps:get(radius, Player),

        %% Move, then clamp to arena so balls cannot leave the boundary.
        NewX = clamp(X + Dx * ?SPEED, R, ?ARENA_W - R),
        NewY = clamp(Y + Dy * ?SPEED, R, ?ARENA_H - R),
        Player#{x => NewX, y => NewY}
    end, Players).


%%% Clamps Value between Min and Max.
clamp(Value, Min, Max) ->
    max(Min, min(Max, Value)).


%%% Checks all pairs of balls for overlap and logs a warning.
%%% Two balls collide when the distance between their centers
%%% is less than the sum of their radii.
%%% No gameplay effect for now.
check_collisions(Players) ->
    PlayerList = maps:to_list(Players),
    check_pairs(PlayerList).

check_pairs([]) -> ok;
check_pairs([_]) -> ok;
check_pairs([{IdA, A} | Rest]) ->
    lists:foreach(fun({IdB, B}) ->
        Dist = distance(A, B),
        MinDist = maps:get(radius, A) + maps:get(radius, B),
        case Dist < MinDist of
            true ->
                print_cli("{collision} ~s and ~s are overlapping (dist=~.1f)",
                    [IdA, IdB, Dist]);
            false ->
                ok
        end
    end, Rest),
    check_pairs(Rest).


%%% Euclidean distance between the centers of two player maps.
distance(A, B) ->
    Dx = maps:get(x, A) - maps:get(x, B),
    Dy = maps:get(y, A) - maps:get(y, B),
    math:sqrt(Dx * Dx + Dy * Dy).


%%% Sends the payload to all connected WS handler pids.
broadcast(Pids, Payload) ->
    lists:foreach(fun(Pid) ->
        Pid ! {game_state, Payload}
    end, Pids).


%%% Encodes the full player state as a JSON binary.
%%% Output: {"players":{"alice":{"x":100.0,"y":200.0,"r":20},...}}
encode_state(Players) ->
    Fields = maps:fold(fun(PlayerId, Player, Acc) ->
        Entry = io_lib:format(
            "\"~s\":{\"x\":~.2f,\"y\":~.2f,\"r\":~p}",
            [
                PlayerId,
                maps:get(x, Player),
                maps:get(y, Player),
                maps:get(radius, Player)
            ]
        ),
        [Entry | Acc]
    end, [], Players),
    Joined = lists:join(",", Fields),
    iolist_to_binary(["{\"players\":{", Joined, "}}"]).