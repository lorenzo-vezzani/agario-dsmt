%%% ---------------
%%% Module description
%%% 
%%% -TODO
%%% ---------------

-module(egs_games_registry).
-export([
    start/0, 
    register/2, 
    unregister/1, 
    lookup/1, 
    all/0
]).

start() ->
    ets:new(game_registry, [named_table, public, {read_concurrency, true}]),
    ok.

register(GameId, Pid) ->
    ets:insert(game_registry, {GameId, Pid}).

unregister(GameId) ->
    ets:delete(game_registry, GameId).

lookup(GameId) ->
    case ets:lookup(game_registry, GameId) of
        [{GameId, Pid}] -> {ok, Pid};
        []              -> {error, not_found}
    end.

all() ->
    ets:tab2list(game_registry).