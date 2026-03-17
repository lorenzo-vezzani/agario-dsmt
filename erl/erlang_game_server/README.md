# egs

Simple multiplayer spacebar-pressing game built with Erlang/OTP and Cowboy WebSockets.
Each player presses spacebar, the game server collects all inputs and broadcasts
the updated counters to all connected players every 20ms.

## Dependencies

- Erlang/OTP 28+
- rebar3
- Cowboy 2.10.0 (declared in `rebar.config`)

## Project structure
```
src/
├── egs_node_entry_point.erl    # application entry point, starts Cowboy
├── egs_node_sup.erl            # top-level supervisor
├── egs_games_mgmt.erl          # dynamic supervisor for game processes
├── egs_game_module.erl         # gen_server: game state, tick, broadcast
├── egs_games_registry.erl      # ETS-based registry: game_id -> pid
└── egs_websocket_handler.erl   # WebSocket handler, one process per client
```

## Running
```bash
rebar3 get-deps
rebar3 compile
rebar3 shell
```

## Creating a game

Once the shell is running, create a game from the Erlang prompt:
```erlang
egs_games_mgmt:start_game(<<"game-1">>).
```

Other useful shell commands:
```erlang
%% number of running games
egs_games_mgmt:game_count().

%% list all games with their pids
egs_games_mgmt:list_games().

%% stop a game
egs_games_mgmt:stop_game(<<"game-1">>).

%% inspect internal state of a game process
{ok, Pid} = egs_games_registry:lookup(<<"game-1">>).
sys:get_state(Pid).
```

## Testing in the browser

Open `test_agario.html` in two separate browser tabs.

The game must be created in the Erlang shell **before** opening the browser tabs.
If you open the browser before creating the game, the WebSocket handler will not
find the game in the registry and the join will silently fail.

Press spacebar or click the SPACE button. Both tabs will show the counters
of all connected players, updated in real time.

## Architecture notes

Each browser connection spawns a dedicated `egs_websocket_handler` process.
On connection, `websocket_init/1` is used (not `init/2`) to register the client
with the game server. This is important: `init/2` is called during the HTTP→WebSocket
upgrade and the process is not yet fully stable. Using `init/2` for the join causes
the game server monitor to immediately detect the process as `noproc` and drop it.
`websocket_init/1` is called after the upgrade is complete and the process is ready.
```
browser <--WS--> ws_handler process (one per client)
                      |
                 cast / info
                      |
               game_server (one per game, holds state)
```
