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

    % extract token from parameters
    #{token := Token} = cowboy_req:match_qs([token], Req),

    GameId = binary:decode_hex(GameIdHex),

    print_cli("{init/2} game=~s player=~s", [GameId, PlayerId]),

    % Construct state object
    State = #{
        game_id => GameId, 
        player_id => PlayerId,
        token => Token
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
    GameId = maps:get(game_id, State),
    PlayerId = maps:get(player_id, State),
    Token = maps:get(token, State),

    % Send the token
    case egs_game_module:token_auth_client(GameId, PlayerId, Token) of
        ok ->
            print_cli("{websocket_init/1} Client ~s token sent", [PlayerId]),
            
            % then ask for auth
            case egs_game_module:player_ask_auth(GameId, PlayerId, self()) of
                ok ->
                    print_cli("{websocket_init/1} Client ~s auth initiated", [PlayerId]),
                    {ok, State};

                _ ->
                    print_cli("{websocket_init/1} Client ~s auth not initiated", [PlayerId]),
                    {reply, {close, 1008, <<"access_denied">>}, State}
            end;

        _ ->
            print_cli("{websocket_init/1} Client ~s token not sent", [PlayerId]),
            {reply, {close, 1008, <<"access_denied">>}, State}
    
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

%%% Called when the GameProcess has received both tokens and authenticated the client
websocket_info({auth, ok}, State) -> 
    GameId = maps:get(game_id, State),
    PlayerId = maps:get(player_id, State),

    % Finally join the game server
    case egs_game_module:player_join(GameId, PlayerId) of
        ok ->
            print_cli("{websocket_init/1} Game ~s - joined by ~s", [GameId, PlayerId]),
            {reply, {text, <<"{\"type\": \"auth_ok\"}">>}, State};

        _ ->
            print_cli("{websocket_init/1} Game ~s not found, closing player ~s", [GameId, PlayerId]),
            {reply, {close, 1008, <<"game_not_found">>}, State}

    % NOTE: from now on the game server will send messages to this pid on every tick.
    % they will be {game_state, Payload} messages, to be sent to the player
    end;

%%% Called when the GameProcess has received both tokens
%%% BUT the authentication has gone wrong
websocket_info({auth, {error, Reason}}, State) ->
    % juts print
    PlayerId = maps:get(player_id, State),
    print_cli("{websocket_info/2} Client ~s auth denied: ~p", [PlayerId, Reason]),

    % send acces denied to the client
    {reply, {close, 1008, <<"access_denied">>}, State};

%%% {game_state, Payload} is sent by game server on every tick
%%% Payload is JSON, just forward it to the browser as a text weboscket frame.
websocket_info({game_state, Payload}, State) ->
    %%% uncomment for full debug, NOTE: a print every 20ms
    % print_cli("{websocket_info/2} sending to browser: ~s", [Payload]),
    {reply, {text, Payload}, State};

%%% {gameover, Payload} is sent by game server on game ended
websocket_info({gameover, Payload}, State) ->
    print_cli("{websocket_info/2} gameover payload received", []),
    {reply, {text, Payload}, State};

% game server is closing all connections
websocket_info({close, 1000, <<"gameover">>}, State) ->
    print_cli("{websocket_info/2} gameover close received", []),
    {reply, {close, 1001, <<"gameover">>}, State};

%%% Catch-all for unexpected messages from other processes (just print and then ignore)
websocket_info(Msg, State) ->
    print_cli("{websocket_info/2} unexpected message: ~p", [Msg]),
    {ok, State}.


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
    egs_game_module:player_leave(
        maps:get(game_id, State),
        maps:get(player_id, State)
    ),
    
    ok.