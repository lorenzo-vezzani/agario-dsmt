%%% ---------------
%%% Module description
%%% 
%%% Application entry point for the EGS node.
%%% Responsible for:
%%%   - starting the ETS game registry
%%%   - starting the Cowboy WebSocket listener
%%%   - starting the top-level supervisor
%%% ---------------

-module(egs_node_entry_point).
-behaviour(application).
-export([start/2, stop/1]).


%%% Module specific cli print
print_cli(Text, Args) ->
    io:format("[NODE INIT][~p] " ++ Text ++ "~n", [self()] ++ Args).


%%% Starts the application.
%%% Called automatically by OTP when the application is started.
%%%
%%% StartType - type of start (normal, or failover/takeover in distributed OTP)
%%% StartArgs - arguments defined in the .app file, usually []
%%%
%%% Returns {ok, Pid} (from the top-level supervisor, start_link),
%%%  which OTP requires to track the supervision tree.
start(_StartType, _StartArgs) ->
    
    %% Define the routing table for Cowboy
    %% '_' matches any hostname
    %% The route "/ws/:game_id/:player_id" binds two path segments as variables:
    %%   game_id   - identifies which game session to join
    %%   player_id - identifies the player within that session
    %% All matching requests are handled by egs_websocket_handler.
    DispatchWs = cowboy_router:compile([{
            '_', 
            [{
                "/ws/:game_id/:player_id", 
                egs_websocket_handler, 
                []
            }]
    }]),

    %% Start a plain HTTP listener named 'ws' on port 49153.
    %% Cowboy will upgrade incoming HTTP requests to WebSocket
    %% automatically when the handler returns {cowboy_websocket, ...}.
    %%
    %% Arguments:
    %%   ws                          - listener name (atom), used to stop it later
    %%   [{port, 49153}]             - TCP transport options
    %%   #{env => #{dispatch => ...}} - protocol options, contains the routing table
    {ok, _} = cowboy:start_clear(ws,
        [{port, 49153}],
        #{env => #{dispatch => DispatchWs}}
    ),

    %% Start the top-level supervisor, which in turn starts the game
    %% management supervisor and all persistent worker processes.
    %% OTP requires start/2 to return the pid of the top-level supervisor.
    egs_node_sup:start_link().


%%% Stops the application cleanly.
%%% Called automatically by OTP during shutdown.
%%%
%%% State - the term returned by start/2, ignored here
stop(_State) ->
    
    %% Stop the Cowboy listener gracefully.
    %% This closes all open WebSocket connections before shutting down.
    cowboy:stop_listener(ws),
    ok.