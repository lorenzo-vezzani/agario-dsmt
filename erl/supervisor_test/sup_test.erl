%%%-------------------------------------------------------------------
%%% @author carlomazzanti
%%% @copyright (C) 2026, <COMPANY>
%%% @doc
%%%
%%% Small supervisor implementation for testing the
%%% Java-Erlang communication
%%%
%%% @end
%%% Created : 02. apr 2026 16:57
%%%-------------------------------------------------------------------
-module(sup_test).
-author("carlomazzanti").

%% API
-export([start/0, stats/1]).

start() ->
  Pid = spawn(fun loop/0),
  register(supervisor_mb, Pid),
  io:format("Supervisor at ~p~n", [Pid]),
  Pid.

stats(Pid) ->
  Pid ! {send_stats}.

loop() ->
  receive
    { From, new_lobby_req, ReqId, Payload } ->
      io:format("Ricevuto: new_lobby_req da ~p: ~p~n", [From, Payload]),
      From ! {self(), new_lobby_resp, ReqId, {ok, "192.168.1.10", 100, "lobby1"}};

    { From, join_lobby_req, ReqId, Payload } ->
      io:format("Ricevuto: join_lobby_req ~p~n", [Payload]),
      From ! {self(), join_lobby_resp, ReqId, {ok}};

    { From, get_lobbies_req, ReqId, Payload} ->
      io:format("Ricevuto: get_lobbies_req ~p~n", [Payload]),
      From ! {self(), get_lobbies_resp, ReqId, {ok, [
        {"192.168.1.10", 100, "lobby1", 1},
        {"192.168.1.11", 101, "lobby2", 2},
        {"192.168.1.13", 103, "lobby3", 3},
        {"192.168.1.65", 49153, "game", 1}
      ]}};

    {send_stats} ->
      io:format("Sending stats...~n", []),
      Json = "{
                \"type\": \"gameover\",
                \"ordered_balls\": [
                  {
                    \"id\": \"prova1\",
                    \"x\": 0,
                    \"y\": 1060.6,
                    \"r\": 20
                  }
                ],
                \"stats\": [
                  {
                    \"id\": \"prova1\",
                    \"kills\": 1,
                    \"deaths\": 0
                  },
                  {
                    \"id\": \"prova2\",
                    \"kills\": 0,
                    \"deaths\": 2
                  }
                ]
              }",
      {springboot_mbox, 'springboot_node@192.168.1.65'} ! {self(), stats_req, 123, {Json}};

    Msg -> io:format("Ricevuto: ~p~n", [Msg])
  end,
  loop().