%%% ---------------
%%% Module description
%%%
%%% Supervisor for all game processes and registry of current games.
%%%  - Supervision of egs_game_module proceesses
%%%  - ETS tabple is created at startup and automatically detroyed with the process
%%%
%%% List of functions:
%%%   start_game/1      - spawns a new game process
%%%   stop_game/1       - stops a game process, given a game_id
%%%   game_count/0      - get the number of current games
%%%   list_games/0      - list all {game_id, pid} pairs of current games
%%%   lookup/1          - find the pid of a game by game_id
%%%   register_game/2   - called by game processes to register themselves
%%%   unregister_game/1 - called by game processes to unregister on exit
%%% 
%%% list_games,     lookup,     register_game,  unregister_game are just wrap of
%%% tab2list,       lookup,     inster,     delete
%%% ---------------


-module(egs_supervisor).
-behaviour(supervisor).
-export([
    start_link/0, 
    init/1,
    start_game/1,
    stop_game/2,
    game_count/0,
    list_games/0,
    lookup/1,
    register_game/2,
    unregister_game/1
]).

-define(GAME_PROC_TABLE,    game_proc_table).

-define(NODES_SUP, 'nodes_supervisor@10.2.1.11').


% Module specific cli print
print_cli(Text, Args) -> egs_utils:print_cli("SUPERVIS.", Text, Args).


%%% Starts this supervisor and registers it locally under the module name.
%%% Also creates the ETS registry table.
%%% Called by egs_node_sup as part of the supervision tree startup.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%%% Initializes the supervisor strategy and child template.
%%% Initializes the ETS table
%%% Called automatically immediately after start_link/0.
init([]) ->

    %% Create the ETS table that ok key-values: {game_id, pid}
    ets:new(

        % Table name
        ?GAME_PROC_TABLE, 
    
        % options
        [
            % named_table, to access by name instead of table reference
            named_table, 
            % public: any process can read and write
            % need this for game processes to regitser and unregister
            public
        ]
    ),
    print_cli("{init/1} ETS registry created", []),

    % supervisor options
    SupervisorSpec = #{

        % Children strategy: simple_one_for_one: 
        %      all children share the same specification (template),
        %      all are added dynamically at runtime with start_child/2
        strategy  => simple_one_for_one,

        % TODO explain: is this restart strategy for the children or for this supervisor itself?
        % TODO then explain restart strategy

        % intensity and period define the maximum restart frequency of the children controlled
        % children (games) are  temporary, so never restarted
        % we would just risk restarting a game in a non-consistent state
        intensity => 0,            % no restarts
        period    => 1             % reference period
    },
    print_cli("{init/1} Supervisor options set", []),

    % Specification of children controlled (this is a supervisor of these children)
    % restart: temporary: means that a crashed game process is NOT restarted automatically.
    %   these children (games) are temporary, so never restarted
    %   and we would just risk restarting a game in a non-consistent state

    ChildSpec = [
        #{
            % egs_game_module: game functionalities
            id       => egs_game_module,

            % module entry point (and args)
            start    => {egs_game_module, start_link, []},

            % module type
            type     => worker, % standard process, not supervisor
        
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
%%% GameId: game identifier, like <<"game-1">>
%%%
%%% Returns {ok, Pid} on success, or {error, Reason} if the process fails to start.
start_game(GameId) ->

    % check that this GameId is not already active
    case lookup(GameId) of

        {error, not_found} ->
            print_cli("{start_game/1} starting game id=~s", [GameId]),
            supervisor:start_child(?MODULE, [GameId]);

        % game found, so conflict on GameId
        {ok, _} ->
            print_cli("{start_game/1} game id=~s already exists", [GameId]),
            {error, already_exists}
    end.


%%% Terminates the game process associated of GameId.
%%% lookup pid in ETS, then asks the supervisor to terminate that child. 
%%% The game process will run its terminate/2 callback, which unregisters it from ETS.
stop_game(GameId, Stats) ->
    print_cli("{stop_game/1} Request to stop game_id=~s", [GameId]),

    % perform TES lookup of GameId
    case lookup(GameId) of

        % if ok, and Pid is given back
        {ok, Pid} ->
            % call to supervisor to terminate this child
            supervisor:terminate_child(?MODULE, Pid),

            % unregister from ets this pid
            % NOT NECESSARY if game process behaves normally (unregisters himself)
            % but needed if it crashes without unregistering
            
            %% contacting the supervisor to notify that a game is terminated
            gen_server:cast({nodes_supervisor, 'nodes_supervisor@10.2.1.11'}, {game_terminated, GameId, Stats}),

            unregister_game(GameId),

            % return ok
            print_cli("{stop_game/1} Game_id=~s stopped", [GameId]),
            ok;

        % if not found, print to log and return error
        {error, _} = Err -> 
            print_cli("{stop_game/1} error", []),

            % propagate error (format is {error, not_found})
            Err
    end.


%%% Returns the number of game processes
game_count() ->

    % given that in the table there are just and only running processes,
    % we can get the size of the table to infer the number of processes
    GameProcCount = ets:info(?GAME_PROC_TABLE, size),
    print_cli("{game_count/0} count=~p", [GameProcCount]),
    GameProcCount.


%%% Returns the full list of running games as array of {GameId, Pid} pairs.
list_games() ->
    print_cli("{list_games/0} called", []),
    % just use the tab2list function of ETS (to list)
    ets:tab2list(?GAME_PROC_TABLE).


%%% Lookup the pid of a game, given a GameId
%%% Returns {ok, Pid} if found, {error, not_found} otherwise.
lookup(GameId) ->
    % ETS lookup, given the registry name
    case ets:lookup(?GAME_PROC_TABLE, GameId) of

        % if result is return, just return the pid
        [{GameId, Pid}] -> {ok, Pid};

        % if not found, return not_found
        []              -> {error, not_found}
    end.


%%% register a game process in the ETS table.
%%% Called by egs_game_module:init/1 immediately after the process starts.
%%% GameId: the game identifier
%%% Pid:    the pid of the game process (self() of the game prcess)
register_game(GameId, Pid) ->
    print_cli("{register_game/2} game=~s pid=~p", [GameId, Pid]),
    ets:insert(?GAME_PROC_TABLE, {GameId, Pid}).


%%% Remove game from the table.
%%% Called by egs_game_module:terminate/2 when the game process is shutting down.
unregister_game(GameId) ->
    print_cli("{unregister_game/1} game=~s", [GameId]),
    ets:delete(?GAME_PROC_TABLE, GameId).
