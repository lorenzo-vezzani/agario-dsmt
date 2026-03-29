-module(job_process).
-behaviour(gen_server).

-export([start_link/2]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2]).

%% called for creating the process
start_link(JobId, Job) ->
  gen_server:start_link(?MODULE, {JobId, Job}, []).

%% called by process created by start_link for initialization
init({JobId, Job}) ->
  io:format("job_process STARTED on node ~p~n", [node()]),
  {ok, #{id => JobId, job => Job}}.

%% called on message arrival by the process
handle_info({ws_msg, Msg}, State) ->
  io:format("got ws msg: ~p~n", [Msg]),
  {noreply, State};

handle_info(_, State) ->
  {noreply, State}.

handle_call(_, _From, State) ->
  {reply, ok, State}.

handle_cast(_, State) ->
  {noreply, State}.