-module(egs_fault_tolerance).
-behaviour(gen_server).

-export([start_link/2, get_state/0]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2]).

-define(HEARTBEAT_TIMEOUT, 3500).
-define(CHECK_INTERVAL, 1000).

-record(state, {
    nodes = [],
    leader = undefined,
    last_heartbeat = 0,
    waiting_leader = false,
    port = undefined
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

get_state() ->
    gen_server:call(?MODULE, get_state).

handle_info({heartbeat, LeaderNode}, State) ->

    Now = erlang:monotonic_time(millisecond),

    %% [ONLY FOR DEBUG PURPOSE]
    %% print_cli("[HEARTBEAT] New heartbeat from leader received <~p> from ~p", [Now, LeaderNode]),

    {noreply, State#state{ leader = LeaderNode, last_heartbeat = Now }};

handle_info(send_heartbeat, State) ->
    case State#state.waiting_leader of
        false ->  gen_server:cast( {nodes_supervisor, State#state.leader}, {egs_heartbeat, node()});
        true -> ok
    end,

    erlang:send_after(?CHECK_INTERVAL, self(), send_heartbeat),
    {noreply, State};

handle_info({new_leader, LeaderId}, State) ->

    ShouldClosePort =
        State#state.port =/= undefined andalso extract_ip(node()) =/= extract_ip(LeaderId),

    NewState =
        case ShouldClosePort of
            true ->
                print_cli("[TEMPORARY SUPERVISOR] A new supervisor has shown. I will be killed", []),
                port_close(State#state.port),
                State#state{port = undefined};

            false ->
                State
        end,

    print_cli("[ELECTION] New leader confirmed: ~p", [LeaderId]),
    egs_supervisor:new_leader(LeaderId),

    Now = erlang:monotonic_time(millisecond),
    
    erlang:send_after(?CHECK_INTERVAL, self(), check_heartbeat),
    
    {noreply, NewState#state{ last_heartbeat = Now, leader = LeaderId, waiting_leader = false }};

handle_info(check_heartbeat, State) when State#state.waiting_leader == true ->
    donothing;

handle_info(check_heartbeat, State = #state{last_heartbeat = Last, leader = Leader, nodes = Nodes}) ->
    Now = erlang:monotonic_time(millisecond),

    NewState =
        case Now - Last > ?HEARTBEAT_TIMEOUT of

            true ->
                NewNodes = lists:filter(fun(N) -> extract_ip(N) =/= extract_ip(Leader) end, Nodes),
                print_cli("[HEARTBEAT-TIMEOUT] Leader suspected dead", []),

                NewLeader = select_minimum_ip_node(NewNodes),
                print_cli("[ELECTION] New leader selected: ~p", [NewLeader]),

                Port =
                    case NewLeader == node() of
                        true ->
                            NodesListStr = "[" ++ string:join( [ "'" ++ atom_to_list(N) ++ "'" || N <- State#state.nodes ], "," ) ++ "]",
                            Cmd = "./become_leader.sh " ++ extract_ip(node()) ++ " \"" ++ NodesListStr ++ "\"",
                            print_cli("[LAUNCHING LEADER] ~s", [Cmd]),
                            open_port({spawn, Cmd}, [binary, use_stdio, exit_status]);

                        false ->
                            undefined
                    end,

                State#state{ waiting_leader = true, port = Port, nodes = NewNodes };

            false ->
                %% reschedule check
                erlang:send_after(?CHECK_INTERVAL, self(), check_heartbeat),
                State
        end,

    {noreply, NewState};

handle_info({node_joining, NodeId}, State) ->
    print_cli("[NEW NODE] New node joining ~p", [NodeId]),
    NewNodesList = [NodeId | State#state.nodes],
    NewState = State#state{nodes = NewNodesList},
    {noreply, NewState};    

handle_info({node_leaving, NodeId}, State) ->
    print_cli("[REMOVE NODE] New node removing ~p", [NodeId]),
    NewNodesList = lists:delete(NodeId, State#state.nodes),
    NewState = State#state{nodes = NewNodesList},
    {noreply, NewState};

%%% this handles the output from the open port process ie the new supervisor 
handle_info({Port, {data, Data}}, State) when is_port(Port) ->
    print_cli("[TEMPORARY SUPERVISOR] ~s", [Data]),
    {noreply, State};

handle_info(_Info, State) -> 
    print_cli("Unrecognizedd msg: ~s", [_Info]),
    {noreply, State}.

handle_call(get_state, _From, State) ->
    {reply, State, State};

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
