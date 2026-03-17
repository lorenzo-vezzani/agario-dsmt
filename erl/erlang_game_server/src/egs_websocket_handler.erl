%%% ---------------
%%% Module description
%%%
%%% WebSocket handler for a single connected player.
%%% One process of this module is spawned by Cowboy for each browser connection.
%%%
%%% Lifecycle:
%%%   1. init/2             - extract game_id and player_id from the URL, upgrade to WS
%%%   2. websocket_init/1   - process is now stable, register with the game server
%%%   3. websocket_handle/2 - handle incoming messages from the browser
%%%   4. websocket_info/2   - handle messages from other Erlang processes (e.g. game server)
%%%   5. terminate/3        - connection closed, unregister from the game server
%%% ---------------

-module(egs_websocket_handler).
-export([
    init/2, 
    websocket_init/1, 
    websocket_handle/2, 
    websocket_info/2, 
    terminate/3
]).


%%% Module specific cli print
print_cli(Text, Args) ->
    io:format("[WebSocket][~p] " ++ Text ++ "~n", [self()] ++ Args).

    %% example of usage
    % print_cli("Game = ~s, Player = ~s", [GameId, PlayerId]).
    % print_cli("Timeout", []).


%%% Called by Cowboy when a new HTTP request arrives on the WebSocket route.
%%% Extracts game_id and player_id from the URL path bindings and
%%% tells Cowboy to upgrade the connection to WebSocket protocol.
%%%
%%% Note: at this point the WebSocket process is not yet fully initialized.
%%% Do NOT register with the game server here — use websocket_init/1 instead.
%%%
%%% Req  - Cowboy request object, contains headers, bindings, etc.
%%% Opts - handler options passed from the routing table (empty list here)
%%%
%%% Returns {cowboy_websocket, Req, State} to trigger the HTTP->WS upgrade.
init(Req, _Opts) ->
    
    % extract game_id and player_id from request
    GameId   = cowboy_req:binding(game_id,   Req),
    PlayerId = cowboy_req:binding(player_id, Req),
    print_cli("{init/2} game=~s player=~s", [GameId, PlayerId]),

    % Construct state object
    State = #{game_id => GameId, player_id => PlayerId},

    % Return {cowboy_websocket, Req, State} to trigger the HTTP->WS upgrade
    {cowboy_websocket, Req, State}.


%%% Called by Cowboy AFTER the WebSocket upgrade is fully complete.
%%% The process is now stable and can safely be monitored by other processes,
%%% we can now register the player-game with the game server.
%%%
%%% State - the state object built in init/2
%%%
%%% Returns {ok, State} to enter the WebSocket message loop.
websocket_init(State) ->
    
    % Extract game id and player id
    GameId   = maps:get(game_id, State),
    PlayerId = maps:get(player_id, State),
    print_cli("{websocket_init/1} Game ~s - joined by ~s", [GameId, PlayerId]),
    
    %% Register this process (the webSocket handler process) with the game server.
    egs_game_module:join(GameId, PlayerId),

    %%% NOTE: from now on the game server will send messages to this pid on every tick.
    % they will be {game_state, Payload} messages, to be sent to the player

    {ok, State}.


%%% Handler of incoming messages from client broswer, 
%%%     it is called when a text or binary frame arrives from the browser.
%%%
%%% Matches on the message content:
%%%   "spacebar" - player pressed spacebar, forward the event to the game server
%%%   anything else - log and ignore
%%%
%%% Returns {ok, State} to keep the connection open without sending a reply.
websocket_handle({text, Msg}, State) ->

    %%% uncomment for full debug, NOTE: a print every 20ms
    % print_cli("{websocket_handle/2} received: ~p", [Msg]),
    case parse_direction(Msg) of
        {ok, Dx, Dy} ->
            egs_game_module:set_direction(
                maps:get(game_id, State),
                maps:get(player_id, State),
                {Dx, Dy}
            );
        error ->
            print_cli("{websocket_handle/2} unknown message, ignoring", [])
    end,
    {ok, State};

%% Separate handler for non-text messages
%% TODO remove if not used (or just print empty error message, without printing the whole frame)
websocket_handle(Frame, State) ->
    print_cli("{websocket_handle/2} received non-text frame: ~p", [Frame]),
    {ok, State}.

%%% Parses a JSON direction message from the browser.
%%% Expected format: {"dx":0.71,"dy":-0.71}
%%% Returns {ok, Dx, Dy} or error.
parse_direction(Msg) ->
    try
        %% Simple manual parse to avoid jsx dependency.
        %% Extracts dx and dy values from the JSON string.
        {match, [DxStr]} = re:run(Msg, "\"dx\":(-?[0-9.]+)",
            [{capture, all_but_first, binary}]),
        {match, [DyStr]} = re:run(Msg, "\"dy\":(-?[0-9.]+)",
            [{capture, all_but_first, binary}]),
        Dx = binary_to_float(DxStr),
        Dy = binary_to_float(DyStr),
        {ok, Dx, Dy}
    catch
        _:_ -> error
    end.


%%% Called when another Erlang process sends a message to this pid.
%%%
%%% {game_state, Payload} - sent by the game server on every tick.
%%%   Payload is a JSON binary, e.g. {"players":{"alice":5,"bob":3}}
%%%   Forward it to the browser as a text WebSocket frame.
websocket_info({game_state, Payload}, State) ->
    %%% uncomment for full debug, NOTE: a print every 20ms
    % print_cli("{websocket_info/2} sending to browser: ~s", [Payload]),
    {reply, {text, Payload}, State};

%%% Catch-all for unexpected messages from other processes (just print and then ignore)
websocket_info(Msg, State) ->
    print_cli("{websocket_info/2} received unexpected message: ~p", [Msg]),
    {ok, State}.


%%% Automatically Called when the WebSocket connection closes (for any reason)
%%% This unregister this player from the game server
%%%
%%% Reason - why the connection closed, e.g. {remote, 1001, <<>>} for
%%%          a normal browser tab close, or timeout for an idle connection
terminate(Reason, _Req, State) ->

    % print to cli
    print_cli("{terminate/3} reason=~p player=~s",
        [Reason, maps:get(player_id, State, <<"unknown">>)]),
    
    % Notify the game process that this player has left.
    % done to remove/cleanup any resources used
    egs_game_module:leave(
        maps:get(game_id, State),
        maps:get(player_id, State)
    ),
    
    ok.