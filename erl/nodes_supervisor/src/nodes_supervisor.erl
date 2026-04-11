%%% todo add a n_player field to game proc map
%%% return game process list as [{ip_addr, port, lobby_id, n_players}, ...]

%%%-------------------------------------------------------------------
%% @doc nodes_supervisor as a gen_server
%% Manages node load balancing and game registry
%%%-------------------------------------------------------------------

-module(nodes_supervisor).
-behaviour(gen_server).

%% Public API
-export([start_link/0, start_game/0, game_terminated/2, token_auth/3, get_games_list/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-define(INITIAL_NODES, [
    'egs@10.2.1.4',
    'egs@10.2.1.5',
    'egs@10.2.1.6'
]).

-define (WS_PORT, 49153).

-define(JAVA_NODE, 'springboot_node@10.2.1.13').

%% Internal state of the gen_server
-record(state, {
    %% Mapping GameId => {NodeId, n_players}
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
    gen_server:call(?SERVER, {start_game}).


%% Asynchronous cast: returns ok or {error, not_found}
%% After a game termination notified by someone of the workers, the local maps are updated accorrdingly
game_terminated(GameId, Stats) ->
    gen_server:cast(?SERVER, {game_terminated, GameId, Stats}).


%% This api allows a player to be identified by the relative token in the target game server
token_auth(Token, PlayerId, GameId) ->
    gen_server:call(?SERVER, {token_auth, Token, PlayerId, GameId}).


%% Synchronous call: returns the game list in the form of: {game-id, node}
get_games_list() ->
    gen_server:call(?SERVER, get_games_list).


%%% ============================================================
%%%  Callbacks
%%% ============================================================

init([]) ->
    %% Initialize empty state
    print_cli("{init/1} gen_server started", []),
    NodeLoad = maps:from_keys(?INITIAL_NODES, 0),
    {ok, #state{game_proc = #{}, node_load = NodeLoad}}.

%%% ============================================================
%%%  Synch
%%% ============================================================

handle_call({start_game}, _From, State) ->
    {Reply, NewState} = start_game_logic(State),
    {reply, Reply, NewState};


handle_call({token_auth, Token, PlayerId, GameId}, _From, State) ->
    {Reply, NewState} = token_auth_logic(Token, PlayerId, GameId, State),
    {reply, Reply, NewState};


handle_call(get_games_list, _From, State) ->
    {Reply, NewState} = get_games_list_logic(State),

    % converting the game process map into a list (required by java)
    GameList = maps:to_list(Reply),
        
    {reply, GameList, NewState};


handle_call({get_lobbies_req, ReqId, {}}, _From, State) ->
    print_cli("[JAVA-REQ] get_lobbies_req received by ~p: \nReqId=~p", [_From, ReqId]),
    
    {Reply, NewState} = get_games_list_logic(State),

    GameList = maps:to_list(Reply),
    FormattedGameList = lists:map(
        fun({GameId, {NodeId, NPlayers}}) -> {extract_ip(NodeId), ?WS_PORT, binary_to_list(GameId), NPlayers} end, 
        GameList
    ),
    
    {reply, {get_lobbies_resp, ReqId, {ok, FormattedGameList}}, NewState};


handle_call({new_lobby_req, ReqId, {}}, _From, State) ->
    print_cli("[JAVA-REQ] new_lobby_req received by JAVA: \nReqId=~p", [ReqId]),
    
    {Reply, NewState} = start_game_logic(State),

    {reply, {new_lobby_resp, ReqId, Reply}, NewState};


handle_call({join_lobby_req, ReqId, {PlayerId, GameId, Token}}, _From, State) ->
    print_cli("[JAVA-REQ] join_lobby_req received by JAVA: \nReqId=~p \nToken=~p, PlayerId=~p, GameId=~p", [ReqId, Token, PlayerId, GameId]),

    {Reply, NewState} = token_auth_logic(Token, PlayerId, GameId, State),
    
    {reply, {join_lobby_resp, ReqId, Reply}, NewState};

handle_call(_Req, _From, State) ->
    %% Default for unknown calls
    {reply, {error, unknown_request}, State}.


%%% ===============================================================
%%% Async cast
%%% ===============================================================

handle_cast({game_terminated, GameId, Stats}, State) ->
    %% Lookup the game in the registry
    case maps:find(GameId, State#state.game_proc) of

        %% game GameId not present
        error ->
            print_cli("{game_temrinated} game ~s not found", [GameId]),
            {noreply, State};

        {ok, {TargetNode, _PlayerCount}} ->
            %% Update internal state
            NewGameProc = maps:remove(GameId, State#state.game_proc),
            NewNodeLoad = maps:update_with(
                TargetNode, 
                fun(N) -> max(0, N - 1) end,
                State#state.node_load
            ),
            NewState = State#state{
                game_proc = NewGameProc,
                node_load = NewNodeLoad
            },

            %% sending stats to java node (converted to string)
            %% NOTE: i dont know how to model a req_id -> im just using GameId as req_id
            {springboot_mbox, ?JAVA_NODE} ! {stats_req, binary_to_list(GameId), {binary_to_list(Stats)}},

            print_cli("{game_temrinated} Game ~s stopped, tables updated \nStats: ~p", [GameId, Stats]),

            {noreply, NewState}
    end;

handle_cast({join_completed, GameId}, State) ->
    %% incrementing player count for game=GameId
    NewGameProc =
        maps:update_with(GameId, fun({NodeId, NPlayers}) -> {NodeId, NPlayers + 1} end, State#state.game_proc),

    NewState = State#state{ game_proc = NewGameProc, node_load = State#state.node_load },
    {noreply, NewState};

handle_cast({leave_completed, GameId}, State) ->
    %% incrementing player count for game=GameId
    NewGameProc =
        maps:update_with(GameId, fun({NodeId, NPlayers}) -> {NodeId, NPlayers - 1} end, State#state.game_proc),

    NewState = State#state{ game_proc = NewGameProc, node_load = State#state.node_load },
    {noreply, NewState};

handle_cast(_Msg, State) -> {noreply, State}.

%%% ===============================================================
%%% Default functions 
%%% ===============================================================

handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.
code_change(_OldVsn, State, _)  -> {ok, State}.

%%% ============================================================
%%%  Logic implementations
%%% ============================================================

start_game_logic(State) ->
    %% Find the node with the least number of games rn to implement load balancing strategy
    case find_least_loaded_node(State#state.node_load) of

        %% No nodes avaible
        {error, empty_table} = Err ->
            {Err, State};

        {ok, TargetNode} ->
            %% Generate a random 32b game id
            GameId = generate_game_id(),

            %% Contact the local supervisor of the node to start a new game with game-id=GameId
            case rpc:call(TargetNode, egs_supervisor, start_game, [GameId]) of

                {ok, _Pid} ->
                    %% updating internal state
                    NewGameProc =
                        maps:put(GameId, {TargetNode, 0}, State#state.game_proc),

                    NewNodeLoad =
                        maps:update_with(TargetNode,
                                         fun(N) -> N + 1 end,
                                         1,
                                         State#state.node_load),

                    NewState = State#state{
                        game_proc = NewGameProc,
                        node_load = NewNodeLoad
                    },

                    print_cli(
                        "Game ~s successfully started on ~p",
                        [GameId, TargetNode]
                    ),

                    {{ok, extract_ip(TargetNode), ?WS_PORT, binary_to_list(GameId)}, NewState};

                %% rpc bad call
                Reason ->
                    print_cli(
                        "rpc:call failed on node ~p: ~p",
                        [TargetNode, Reason]
                    ),
                    {{error, {node_unavailable, Reason}}, State}
            end
    end.


token_auth_logic(Token, PlayerId, GameIdList, State) ->
    GameId = (list_to_binary(GameIdList)),
    
    %% control wheter the game with id=GameId actually exists
    case maps:find(GameId, State#state.game_proc) of

        %% no existing game
        error ->
            print_cli("{token_auth} game ~s not found", [GameId]),
            {{error, not_found}, State};

        {ok, {TargetNode, _PlayerCount}} ->
            %% communicate to node TargetNode the new token (ie a new client that can play)
            case rpc:call(
                TargetNode,
                egs_game_module,
                token_auth_supervisor,
                [GameId, PlayerId, Token]
            ) of

                ok ->
                    {{ok}, State};

                %% rpc bad call
                Reason ->
                    print_cli(
                        "rpc:call failed on node ~p: ~p",
                        [TargetNode, Reason]
                    ),
                    {{error, {node_unavailable, Reason}}, State}

            end
    end.

get_games_list_logic(State) ->
    {State#state.game_proc, State}.

%%% ============================================================
%%%  Internal utilities
%%% ============================================================

generate_game_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    binary:encode_hex(Bytes).


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

extract_ip(Name) ->
    NameStr = atom_to_list(Name),
    case string:split(NameStr, "@", all) of
        [_, IP] -> IP;
        _ -> NameStr
    end.

print_cli(Text, Args) ->
    %% Print messages with supervisor prefix
    supervisor_utils:print_cli("SUPERVIS.", Text, Args).
