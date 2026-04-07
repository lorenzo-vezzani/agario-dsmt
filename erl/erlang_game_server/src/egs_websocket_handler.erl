%%% ---------------
%%% Module description
%%%
%%% WebSocket handler; Cowboy will spawn a process for every connected player.
%%%
%%% List of functions, listed in the order they are used:
%%%     init/2              - extract game_id and player_id from the URL, upgrade to WS
%%%     websocket_init/1    - register with the game server
%%%     websocket_handle/2  - handle incoming messages from the browser
%%%     websocket_info/2    - handle messages from game server
%%%     terminate/3         - connection closed, unregister from the game server
%%% note that these names are imposed by the Cowboy framework
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
print_cli(Text, Args) -> egs_utils:print_cli("WebSocket", Text, Args).

    %% example of usage
    % print_cli("Game = ~s, Player = ~s", [GameId, PlayerId]).
    % print_cli("Timeout", []).


%%% Called by Cowboy when a new HTTP request arrives on the WebSocket route.
%%% Extracts game_id and player_id from the URL path bindings and
%%% tells Cowboy to upgrade the connection to WebSocket protocol.
%%%
%%% Req  - Cowboy request object, contains headers, bindings, etc.
%%%
%%% Returns {cowboy_websocket, Req, State} to trigger the HTTP->WS upgrade.
init(Req, _Opts) ->
    
    % extract game_id and player_id from request
    GameIdHex = cowboy_req:binding(game_id, Req),
    PlayerId = cowboy_req:binding(player_id, Req),

    GameId = binary:decode_hex(GameIdHex),

    print_cli("{init/2} game=~s player=~s", [GameId, PlayerId]),

    % Construct state object
    State = #{
        game_id => GameId, 
        player_id => PlayerId
    },

    % Return {cowboy_websocket, Req, State} to trigger the HTTP->WS upgrade
    {cowboy_websocket, Req, State}.


%%% Called by Cowboy AFTER the WebSocket upgrade is fully complete.
%%% We can now register the player-game with the game server.
%%%
%%% State - the state object built in init/2
%%%
%%% Returns {ok, State} to enter the WebSocket message loop.
websocket_init(State) ->
    
    % Extract game id and player id from the State map
    GameId   = maps:get(game_id, State),
    PlayerId = maps:get(player_id, State),
    
    % Register this process (the webSocket handler process) with the game server.
    case egs_game_module:join(GameId, PlayerId) of
        ok ->
            print_cli("{websocket_init/1} Game ~s - joined by ~s", [GameId, PlayerId]),
            {ok, State};

        _ ->
            print_cli("{websocket_init/1} Game ~s not found, closing player ~s", [GameId, PlayerId]),
            {reply, {close, 1008, <<"game_not_found">>}, State}

    % NOTE: from now on the game server will send messages to this pid on every tick.
    % they will be {game_state, Payload} messages, to be sent to the player
    end.


%%% Handler for incoming messages from client broswer,
%%%
%%% Returns {ok, State} to keep the connection open without sending a reply.
websocket_handle({text, <<"rejoin">>}, State) ->
    egs_game_module:player_rejoin(
        maps:get(game_id, State),
        maps:get(player_id, State)
    ),
    {ok, State};

websocket_handle({text, Msg}, State) ->

    % uncomment for full debug, NOTE: a print every 20ms
    % print_cli("{websocket_handle/2} received: ~p", [Msg]),

    % inoltrate whatever messgae is sent to the game process
    egs_game_module:player_input(
        maps:get(game_id, State),
        maps:get(player_id, State),
        Msg
    ),

    {ok, State};

%% Separate handler for non-text messages
%% TODO remove if not used (or just print empty error message, without printing the whole frame)
websocket_handle(Frame, State) ->
    print_cli("{websocket_handle/2} received non-text frame: ~p", [Frame]),
    {ok, State}.


%%% websocket_info is called when another Erlang process sends a message to this pid.

%%% {game_state, Payload} is sent by game server on every tick
%%% Payload is JSON, just forward it to the browser as a text weboscket frame.
websocket_info({game_state, Payload}, State) ->
    %%% uncomment for full debug, NOTE: a print every 20ms
    % print_cli("{websocket_info/2} sending to browser: ~s", [Payload]),
    {reply, {text, Payload}, State};

%%% {gameover, Payload} is sent by game server on game ended
websocket_info({gameover, Payload}, State) ->
    print_cli("{websocket_info/2 gameover} sending to browser final JSON", []),
    
    % sending two frames
    {
        reply, 
        [
            % frame 1: json payload
            {text, Payload}, 

            % frame 2: close connection
            {close, 1001, <<"gameover">>}
        ], 
        State
    };

%%% Catch-all for unexpected messages from other processes (just print and then ignore)
websocket_info(Msg, State) ->
    
    print_cli("{websocket_info/2} received unexpected message: ~p", [Msg]),

    case Msg of 

        % server closes connection WITHOUT a proper gamover message:
        % it means that it is crashed
        {close, 1000, <<"gameover">>} ->
            
            % Close this websocket
            % 1011 - internal Server Error
            {close, 1011, <<"gameover">>};

        % unknown message
        {_Type, _Code, _Reason} ->
            {ok, State}
    end.


%%% Automatically Called when the WebSocket connection closes (for any reason)
%%% This unregister this player from the game server
%%%
%%% Reason - why the connection closed, e.g. {remote, 1001, <<>>} for
%%%          a normal browser tab close, or timeout for an idle connection
terminate(Reason, _Req, State) ->


    % print to cli
    try
        {Type, Code, String} = Reason,
        PlayerId = maps:get(player_id, State), 
        
        print_cli("{terminate/3} reason={~p,~p,~p} player=~s",[Type, Code, String, PlayerId])

    % if there are some errors, catch all
    catch
        _:_ -> print_cli("{terminate/3} reason=? player=?", [])
    end,

    
    % Notify the game process that this player has left.
    % done to remove/cleanup any resources used
    egs_game_module:leave(
        maps:get(game_id, State),
        maps:get(player_id, State)
    ),
    
    ok.