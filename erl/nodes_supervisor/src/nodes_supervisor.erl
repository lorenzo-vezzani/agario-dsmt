%%%-------------------------------------------------------------------
%% @doc nodes_supervisor as a gen_server
%% Manages node load balancing and game registry
%%%-------------------------------------------------------------------

-module(nodes_supervisor).
-behaviour(gen_server).

%% Public API
-export([start_link/0, start_game/0, stop_game/1, game_terminated/2, get_games_list/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, register_node/1, unregister_node/1]).

-define(SERVER, ?MODULE).

-define(INITIAL_NODES, [
    'egs@10.2.1.5',
    'egs@10.2.1.6'
]).

-define(JAVA_NODE, 'springboot_node@10.2.1.13').

%% Internal state of the gen_server
-record(state, {
    %% Mapping GameId => NodeId
    game_proc  :: map(),
    %% Mapping NodeId => number of active games
    node_load  :: map()
}).
%%% ============================================================
%%%  API
%%% ============================================================

start_link() ->
    %% Start the gen_server locally
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


%% Synchronous call: returns {ok, GameId, Node} or {error, empty_table}
%% This api starts a game
start_game() ->
    gen_server:call(?SERVER, start_game).


%% Synchronous call: returns ok or {error, not_found}
%% This api stops a game with id=GameId 
stop_game(GameId) ->
    gen_server:call(?SERVER, {stop_game, GameId}).


%% Synchronous call: returns ok or {error, not_found}
%% After a game termination notified by someone of the workers, the local maps are updated accorrdingly
game_terminated(GameId, Stats) ->
    gen_server:call(?SERVER, {game_terminated, GameId, Stats}).


%% Synchronous call: returns the game list in the form of: {game-id, node}
get_games_list() ->
    gen_server:call(?SERVER, get_games_list).


%% Synchronous call: returns {ok} or error if required node already exists
register_node(NodeId) ->
    gen_server:call(?SERVER, {register_node, NodeId}).


%% Synchronous call: returns {ok, count-of-active-processes} or error if required node is not found
unregister_node(NodeId) ->
    gen_server:call(?SERVER, {unregister_node, NodeId}).


%%% ============================================================
%%%  Callbacks
%%% ============================================================


init([]) ->
    %% Initialize empty state
    print_cli("{init/1} gen_server started", []),
    NodeLoad = maps:from_keys(?INITIAL_NODES, 0),
    {ok, #state{game_proc = #{}, node_load = NodeLoad}}.


handle_call(start_game, _From, State) ->
    %% Find node with the least load
    case find_least_loaded_node(State#state.node_load) of

        {error, empty_table} = Err ->
            {reply, Err, State};

        {ok, TargetNode} ->
            GameId = generate_game_id(),

            %% Start the game on the selected node via RPC
            case rpc:call(TargetNode, egs_supervisor, start_game, [GameId]) of
                {ok, Pid} ->
                    %% Update internal state
                    NewGameProc = maps:put(GameId, TargetNode, State#state.game_proc),
                    NewNodeLoad = maps:update_with(TargetNode, fun(N) -> N + 1 end, 1,
                                                State#state.node_load),
                    NewState = State#state{game_proc = NewGameProc,
                                        node_load = NewNodeLoad},

                    print_cli("Game ~s successfully started on ~p", [binary:encode_hex(GameId), TargetNode]),
                    {reply, {ok, GameId, TargetNode, Pid}, NewState};
                {badrpc, Reason} ->
                    print_cli("rpc:call failed on node ~p: ~p", [TargetNode, Reason]),
                    {reply, {error, {node_unavailable, Reason}}, State}
            end

    end;


handle_call({stop_game, GameId}, _From, State) ->
    %% Lookup the game in the registry
    case maps:find(GameId, State#state.game_proc) of

        error ->
            print_cli("{stop_game} game ~s not found", [binary:encode_hex(GameId)]),
            {reply, {error, not_found}, State};

        {ok, TargetNode} ->
            %% Stop the game via RPC
            ok = rpc:call(TargetNode, egs_supervisor, stop_game, [GameId]),

            %% Update internal state
            NewGameProc = maps:remove(GameId, State#state.game_proc),
            NewNodeLoad = maps:update_with(TargetNode, fun(N) -> max(0, N - 1) end,
                                           State#state.node_load),
            NewState = State#state{game_proc = NewGameProc,
                                   node_load = NewNodeLoad},

            print_cli("Game ~s stopped, tables updated", [binary:encode_hex(GameId)]),
            {reply, ok, NewState}
    end;


handle_call({game_terminated, GameId, Stats}, _From, State) ->
    %% Lookup the game in the registry
    case maps:find(GameId, State#state.game_proc) of

        error ->
            print_cli("{game_temrinated} game ~s not found", [binary:encode_hex(GameId)]),
            {reply, {error, not_found}, State};

        {ok, TargetNode} ->
            %% Update internal state
            NewGameProc = maps:remove(GameId, State#state.game_proc),
            NewNodeLoad = maps:update_with(TargetNode, fun(N) -> max(0, N - 1) end,
                                           State#state.node_load),
            NewState = State#state{game_proc = NewGameProc,
                                   node_load = NewNodeLoad},

            %% sending stats to java node
            {springboot_mbox, ?JAVA_NODE} ! {self(), stats_req, GameId, {Stats}},

            print_cli("Game ~s stopped, tables updated \nStats: ~p", [binary:encode_hex(GameId), Stats]),

            {reply, ok, NewState}
    end;


handle_call({register_node, NodeId}, _From, State) ->
    case maps:is_key(NodeId, State#state.node_load) of
        true ->
            {reply, {error, already_registered}, State};

        false ->
            NewNodeLoad = maps:put(NodeId, 0, State#state.node_load),
            print_cli("Node ~p registered", [NodeId]),
            {reply, ok, State#state{node_load = NewNodeLoad}}
    end;

handle_call({unregister_node, NodeId}, _From, State) ->
    case maps:find(NodeId, State#state.node_load) of
        %% node not found
        error ->
            {reply, {error, not_found}, State};

        %% node found, but busy with games
        {ok, Count} when Count > 0 ->
            {reply, {error, node_busy}, State};
        
        %% node found
        {ok, 0} ->
            NewNodeLoad = maps:remove(NodeId, State#state.node_load),
            print_cli("Node ~p unregistered", [NodeId]),
            {reply, ok, State#state{node_load = NewNodeLoad}}
    end;

handle_call(get_games_list, _From, State) ->
    {reply, State#state.game_proc, State}
    ;


handle_call(_Req, _From, State) ->
    %% Default for unknown calls
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.
code_change(_OldVsn, State, _)  -> {ok, State}.


%%% ============================================================
%%%  Internal
%%% ============================================================

generate_game_id() ->
    %% Generate a secure random 32-byte GameId
    crypto:strong_rand_bytes(32).

find_least_loaded_node(NodeLoad) when map_size(NodeLoad) =:= 0 ->
    {error, empty_table};
find_least_loaded_node(NodeLoad) ->
    %% Fold over nodes to find the one with minimum load
    {Node, _Count} = maps:fold(
        fun(Node, Load, {AccNode, AccLoad}) ->
            if Load < AccLoad -> {Node, Load};
               true           -> {AccNode, AccLoad}
            end
        end,
        hd(maps:to_list(NodeLoad)),   %% initial value
        NodeLoad
    ),
    {ok, Node}.

print_cli(Text, Args) ->
    %% Print messages with supervisor prefix
    supervisor_utils:print_cli("SUPERVIS.", Text, Args).