%% ws listener

-module(ws_handler).

-export([init/2, websocket_init/1, websocket_handle/2]).

%% called on http request (asks for upgrade to ws)
init(Req, _State) ->
  %% take job id from URL
  JobId = cowboy_req:binding(job_id, Req),

  %% tell cowboy to upgrade to websocket, give as initial state of ws the map #{job_id => JobId}
  {cowboy_websocket, Req, #{job_id => JobId}}.


%% called after ws handshake
websocket_init(State) ->
  {ok, State}.


%% called on msg arrival from ws
websocket_handle({text, Msg}, State = #{job_id := JobId}) ->
  case ets:lookup(job_table, JobId) of
    [{_, Pid}] ->
      Pid ! {ws_msg, Msg},
      {ok, State};
    [] ->
      {reply, {text, <<"job not found">>}, State}
  end.