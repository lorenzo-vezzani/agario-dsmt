-module(egs_fault_tolerance).
-behaviour(gen_server).

-export([start_link/2]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2]).

-define(HEARTBEAT_TIMEOUT, 3500).
-define(CHECK_INTERVAL, 1000).

-record(state, {
    nodes = [],
    leader = undefined,
    last_heartbeat = 0,
    waiting_leader = false
}).

start_link(Leader, NodeList) ->
    gen_server:start_link({local, fault_tolerance_handler}, ?MODULE, [Leader, NodeList], []).

init([Leader, NodeList]) ->

    print_cli("[FAULT TOLERANCE] Started with Leader: ~p, Nodes: ~p", [Leader, NodeList]),

    Now = erlang:monotonic_time(millisecond),

    erlang:send_after(?CHECK_INTERVAL, self(), check_heartbeat),
    erlang:send_after(?CHECK_INTERVAL, self(), send_heartbeat),

    {ok, #state{
        nodes = NodeList,
        leader = Leader,
        last_heartbeat = Now
    }}.

handle_info({heartbeat, LeaderNode}, State) ->

    Now = erlang:monotonic_time(millisecond),

    %% [ONLY FOR DEBUG PURPOSE]
    %% print_cli("[HEARTBEAT] New heartbeat from leader received <~p> from ~p", [Now, LeaderNode]),

    {noreply, State#state{ leader = LeaderNode, last_heartbeat = Now }};

handle_info(send_heartbeat, State) ->
    case State#state.waiting_leader of
        false ->  gen_server:cast( {nodes_supervisor, State#state.leader}, {egs_heartbeat, node()})
    end,

    erlang:send_after(?CHECK_INTERVAL, self(), send_heartbeat),
    {noreply, state};

handle_info({new_leader, LeaderId}, State) ->
    erlang:send_after(?CHECK_INTERVAL, self(), check_heartbeat),
    %% updating leader in supervisor
    egs_supervisor:new_leader(),
    {noreply, State#state{leader = LeaderId, waiting_leader = false}};

handle_info(check_heartbeat, State = #state{last_heartbeat = Last}) ->
    Now = erlang:monotonic_time(millisecond),
        
    case Now - Last > ?HEARTBEAT_TIMEOUT of
        true ->
            print_cli("[HEARTBEAT-TIMEOUT] Leader suspected dead", []),

            %%% here an election processo must start and a claim must be received
            NewLeader = select_minimum_ip_node(State#state.nodes),
            print_cli("[ELECTION] New leader selected: ~p", [NewLeader]),

            %% if im the new leader ill spawn a dedicated process to run it
            case NewLeader == node() of
                true -> open_port({spawn, "./become_leader.sh"}, [node()])
            end,

            {noreply, State#state{waiting_leader = true}};

        false ->
            erlang:send_after(?CHECK_INTERVAL, self(), check_heartbeat)
    end,

    {noreply, State};

handle_info({node_joining, NodeId}, State) ->
    print_cli("[NEW NODE] New node joining ~p", [NodeId]),
    NewNodesList = [NodeId | State#state.nodes],
    NewState = State#state{nodes = NewNodesList, leader = State#state.leader, last_heartbeat = State#state.last_heartbeat},
    {noreply, NewState};

handle_info({node_leaving, NodeId}, State) ->
    print_cli("[REMOVE NODE] New node removing ~p", [NodeId]),
    NewNodesList = lists:delete(NodeId, State#state.nodes),
    NewState = State#state{nodes = NewNodesList, leader = State#state.leader, last_heartbeat = State#state.last_heartbeat},
    {noreply, NewState}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.


print_cli(Text, Args) -> egs_utils:print_cli("GameLogic", Text, Args).

select_minimum_ip_node(NodeList) ->
    Sorted = lists:sort(fun(A, B) ->
        ip_to_tuple(extract_ip(A)) =< ip_to_tuple(extract_ip(B))
    end, NodeList),
    hd(Sorted).

extract_ip(Name) ->
    NameStr = atom_to_list(Name),
    case string:split(NameStr, "@", all) of
        [_, IP] -> IP;
        _ -> NameStr
    end.

ip_to_tuple(IPStr) ->
    Parts = string:split(IPStr, ".", all),
    list_to_tuple([list_to_integer(P) || P <- Parts]).
