%% creates a new worker on http request

-module(worker_manager).
-behaviour(gen_server).

-export([start_link/0, init/1]).
-export([handle_call/3]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  io:format("worker_manager STARTED on node ~p~n", [node()]),
  ets:new(job_table, [named_table, public, set]),
  {ok, #{}}.

handle_call({start_job, JobId, Job}, _From, State) ->
  {ok, Pid} = job_process:start_link(JobId, Job),

  ets:insert(job_table, {JobId, Pid}),

  {reply, {ok, JobId}, State}.