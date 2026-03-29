%%%-------------------------------------------------------------------
%% @doc game_node top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(game_node_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/ws/:job_id", ws_handler, []}
    ]}
  ]),

  {ok, _} = cowboy:start_clear(
    http_listener,
    [{port, 8080}],
    #{env => #{dispatch => Dispatch}}
  ),

  SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},

  ChildSpecs = [
    #{id => worker_manager,
      start => {worker_manager, start_link, []}}
  ],

  {ok, {SupFlags, ChildSpecs}}.

%% internal functions
