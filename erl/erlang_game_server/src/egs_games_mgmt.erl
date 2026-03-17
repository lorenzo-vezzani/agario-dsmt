%%% ---------------
%%% Module description
%%%
%%% Dynamic supervisor for game processes, and registry of running games.
%%%
%%% This module has two responsibilities:
%%%   1. Supervisor: manages the lifecycle of egs_game_module processes.
%%%      Uses simple_one_for_one strategy, which allows spawning an arbitrary
%%%      number of identical children at runtime via start_game/1.
%%%
%%%   2. Registry: owns an ETS table that maps game_id -> pid.
%%%      The table is created when this supervisor starts and is automatically
%%%      destroyed when this process dies (ETS tables are owned by their creator).
%%%      All game processes register themselves in this table on init and
%%%      unregister on terminate.
%%%
%%% Public API (callable from any process on the node):
%%%   start_game/1  - spawn a new game process
%%%   stop_game/1   - terminate a game process by game_id
%%%   game_count/0  - number of currently running games
%%%   list_games/0  - list of all {game_id, pid} pairs
%%%   lookup/1      - find the pid of a game by game_id
%%%   register/2    - called by game processes to register themselves
%%%   unregister/1  - called by game processes to unregister on exit
%%% ---------------


-module(egs_games_mgmt).
-behaviour(supervisor).
-export([
    start_link/0, 
    init/1,
    start_game/1,
    stop_game/1,
    game_count/0,
    list_games/0,
    lookup/1,
    register/2,
    unregister/1
]).


% Module specific cli print
print_cli(Text, Args) ->
    io:format("[GamesMGMT][~p] " ++ Text ++ "~n", [self()] ++ Args).


%%% Starts this supervisor and registers it locally under the module name.
%%% Also creates the ETS registry table.
%%% Called by egs_node_sup as part of the supervision tree startup.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%%% Initializes the supervisor strategy and child template.
%%% Called automatically by OTP immediately after start_link/0.
%%%
%%% Strategy: simple_one_for_one
%%%   All children share a single child template (egs_game_module).
%%%   Children are not started automatically — they are spawned on demand
%%%   by calling supervisor:start_child/2, which is wrapped by start_game/1.
%%%   This is the standard OTP pattern for pools of identical worker processes.
%%%
%%% intensity => 0, period => 1
%%%   Game processes use restart => temporary, so they are never restarted
%%%   automatically. These values are therefore irrelevant in practice,
%%%   but must still be provided — 0 restarts in 1 second is the safest default.
init([]) ->

    %% Create the ETS table that maps game_id -> pid.
    %% Options:
    %%   named_table      - accessible globally by name 'game_registry'
    %%   public           - any process can read and write
    %%   {read_concurrency, true} - optimizes for concurrent reads (many lookups, few writes)
    ets:new(game_registry, [named_table, public, {read_concurrency, true}]),
    print_cli("{init/1} ETS registry created", []),

    % supervisor options
    SupervisorSpec = #{
        %%% Strategy to adopt on children crash:
        %%      simple_one_for_one: ???
        strategy  => simple_one_for_one,   % ???

        % intensity and period define the maximum restart frequency:
        %   no restarts here
        intensity => 0,            % no restarts
        period    => 1             % reference period
    },
    print_cli("{init/1} Supervisor options set", []),

    % Specification of children controlled (this is a supervisor of these children)
    %% Child template for game processes.
    %% id is ignored in simple_one_for_one - OTP uses the pid to identify children.
    %%
    %% restart => temporary
    %%   A crashed game process is NOT restarted automatically.
    %%   This is intentional: a game that crashes mid-session is likely in a
    %%   corrupt state, and restarting it would create a new empty game with
    %%   the same id, confusing connected clients.
    %%   Connected WebSocket handlers will receive a 'DOWN' message and handle
    %%   the disconnection on their own.
    %%
    %% shutdown => 5000
    %%   When this supervisor shuts down, it gives each game process up to
    %%   5 seconds to terminate cleanly (run terminate/2) before killing it.
    ChildSpec = [
        #{
            % egs_game_module: game functionalities
            id       => egs_game_module,

            % module entry point (and args)
            start    => {egs_game_module, start_link, []},

            % module type
            type     => worker,
        
            % restart: temporary: means that a crashed game process is not restarted automatically
            restart  => temporary,
            
            % shutdown: 5 seconds to terminate cleanly before killing it
            shutdown => 5000
        }
    ],
    print_cli("{init/1} Children specifications set", []),

    % return ok (return to start_link)
    {ok, {SupervisorSpec, ChildSpec}}.


%%% Spawns a new game process with the given GameId.
%%% The game process will register itself in the ETS table during its own init.
%%%
%%% GameId - binary identifying the game, e.g. <<"game-1">>
%%%
%%% Returns {ok, Pid} on success, or {error, Reason} if the process fails to start.
start_game(GameId) ->
    print_cli("{start_game/1} starting game id=~s", [GameId]),
    supervisor:start_child(?MODULE, [GameId]).


%%% Terminates the game process associated with GameId.
%%% Looks up the pid in the ETS registry, then asks the supervisor to
%%% terminate that child. The game process will run its terminate/2 callback,
%%% which unregisters it from ETS.
%%%
%%% Returns ok, or {error, not_found} if no game with that id exists.
stop_game(GameId) ->
    print_cli("{stop_game/1} stopping game id=~s", [GameId]),
    case lookup(GameId) of
        {ok, Pid} -> 
            supervisor:terminate_child(?MODULE, Pid),
            unregister(GameId),
            ok;
        {error, _} = Err -> 
            Err
    end.


%%% Returns the number of game processes currently running.
%%% supervisor:which_children/1 returns the list of all live children.
game_count() ->
    Count = length(supervisor:which_children(?MODULE)),
    print_cli("{game_count/0} count=~p", [Count]),
    Count.


%%% Returns the full list of running games as [{GameId, Pid}] pairs.
list_games() ->
    print_cli("{list_games/0} called", []),
    ets:tab2list(game_registry).


%%% Looks up the pid of a running game by its GameId; reads directly from ETS
%%%
%%% Returns {ok, Pid} if found, {error, not_found} otherwise.
lookup(GameId) ->
    case ets:lookup(game_registry, GameId) of
        [{GameId, Pid}] -> {ok, Pid};
        []              -> {error, not_found}
    end.


%%% Registers a game process in the ETS table.
%%% Called by egs_game_module:init/1 immediately after the process starts.
%%%
%%% GameId - the game identifier
%%% Pid    - the pid of the game process (typically self() from the game process)
register(GameId, Pid) ->
    print_cli("{register/2} game=~s pid=~p", [GameId, Pid]),
    ets:insert(game_registry, {GameId, Pid}).


%%% Removes a game from the ETS table.
%%% Called by egs_game_module:terminate/2 when the game process is shutting down.
%%%
%%% GameId - the game identifier to remove
unregister(GameId) ->
    print_cli("{unregister/1} game=~s", [GameId]),
    ets:delete(game_registry, GameId).