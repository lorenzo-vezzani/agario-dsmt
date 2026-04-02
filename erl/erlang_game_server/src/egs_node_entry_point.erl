%%% ---------------
%%% Module description
%%% 
%%% Application entry point for the node.
%%% 
%%% Starts the cowboy websocket listener
%%% ---------------

-module(egs_node_entry_point).
-behaviour(application).
-export([start/2, stop/1]).

-define(WS_PORT, 49153).
-define(CERT, "cert.pem").
-define(KEY, "key.pem").
-define(APP_NAME, egs).

-define(LIST,       ws_list).

%%% Module specific cli print
print_cli(Text, Args) -> egs_utils:print_cli("NODE INIT", Text, Args).


%%% Starts the application. called automatically when the application is started.
%%%
%%% StartType - type of start (normal, or failover/takeover in distributed OTP)
%%% StartArgs - arguments defined in the .app file, usually []
%%%
%%% Returns {ok, Pid} (passed from the top-level supervisor, start_link),
%%%     This return is required to track the supervision tree.
start(_StartType, _StartArgs) ->
    
    %% Create a map URL to handler
    Websocket_dispatch = cowboy_router:compile([{

            % '_' to match any hostname
            '_', 

            % list of maps
            [{

                % path pattern
                % NOTE: game_id and player_id are dynamic binding variables
                "/ws/:game_id/:player_id", 

                % Handler associated (separate module handler)
                egs_websocket_handler, 

                % initial options passed to the handler on init
                []
            }]
    }]),
    print_cli("{start/2} WebSocket dispatch created", []),

    %% Start a HTTP listener on port 49153.
    %% Cowboy will upgrade incoming HTTP requests to WebSocket
    %% automatically when the handler returns {cowboy_websocket, ...}
    {ok, _} = cowboy:start_tls(

        % name
        ?LIST,

        % options
        [
            {port, ?WS_PORT},
            {certfile, filename:join(code:priv_dir(?APP_NAME), ?CERT)},
            {keyfile,  filename:join(code:priv_dir(?APP_NAME), ?KEY)}
        ],

        % Link this listener to the previous map
        #{env => #{dispatch => Websocket_dispatch}}
    ),
    print_cli("{start/2} WebSocket listeners started on port ~p", [?WS_PORT]),


    %% Start the top-level supervisor, which in turn starts the game mgmt supervisor
    % egs_node_sup:start_link().
    egs_supervisor:start_link().


%%% Stops the application, called automatically by OTP during shutdown.
stop(_State) ->
    
    % Stop the Cowboy listener
    % also all websockets are closed
    cowboy:stop_listener(?LIST),
    print_cli("{stop/1} Listener stopped", []),
    ok.