%%%-------------------------------------------------------------------
%% @doc nodes_supervisor public API
%% @end
%%%-------------------------------------------------------------------

-module(nodes_supervisor_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    nodes_supervisor_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
