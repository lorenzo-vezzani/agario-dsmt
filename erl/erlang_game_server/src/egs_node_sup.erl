%%% ---------------
%%% Module description
%%%
%%% Top-level supervisor for the EGS node.
%%% Owns the supervision tree and ensures that critical processes
%%% are restarted if they crash.
%%%
%%% Children:
%%%   - egs_games_mgmt: dynamic supervisor that manages game server processes
%%% ---------------

-module(egs_node_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).


%%% Module specific cli print
print_cli(Text, Args) ->
    io:format("[NODE SUP.][~p] " ++ Text ++ "~n", [self()] ++ Args).


%%% Starts the top-level supervisor and registers it locally under
%%% the module name, so it can be referenced as egs_node_sup from anywhere
%%% on the same node.
start_link() ->
    print_cli("{start_link/0} supervisor registered", []),

    % return to caller: egs_node_entry_point:start/2
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%%% Initializes the supervisor with its strategy and child specifications.
%%% Called automatically by OTP after start_link/0.
init([]) ->

    % supervisor options
    SupervisorSpec = #{
        %%% Strategy to adopt on children crash:
        %%      one_for_one: If a child crashes, only that child is restarted.
        %%%         This is chosen because, among the strategies that restarts (some) childs,
        %%%         this is the most light, and child (game servers) are indipendent
        strategy  => one_for_one,   % restart only crashed child

        % intensity and period define the maximum restart frequency:
        %   at most 5 restarts in 10 seconds before the supervisor itself gives up.
        intensity => 5,             % 5 restarts MAX in <period>
        period    => 10             % reference period
    },
    print_cli("{init/1} Supervisor options set", []),

    % Specification of children controlled (this is a supervisor of these children)
    ChildSpec = [
        #{
            % egs_games_mgmt: manages the lifecycle of individual game server proces
            id       => egs_games_mgmt,

            % starting point of egs_games_mgmt
            start    => {egs_games_mgmt, start_link, []},
            
            %% egs_games_mgmt is a dynamic supervisor (type: supervisor).
            type     => supervisor,

            % restart: permanent: means it will always be restarted if it crashes
            restart  => permanent,

            % TODO
            shutdown => 5000
        }
    ],
    print_cli("{init/1} Children specifications set", []),

    % return ok (return to start_link)
    {ok, {SupervisorSpec, ChildSpec}}.