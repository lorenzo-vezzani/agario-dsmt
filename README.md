# BallZone: an agar.io-inspired Distributed Game

Project for the **Distributed Systems and Middleware Technologies** course, MSc in Computer Engineering, Università di Pisa (A.Y. 2025/2026).

**Authors:** Carlo Mazzanti, Alessio Simoncini, Lorenzo Vezzani
**Repository:** https://github.com/lorenzo-vezzani/agario-dsmt

## Description

A web-based multiplayer game inspired by agar.io. Each player controls a ball that follows the mouse pointer: the larger ball eliminates the smaller one, while food dots (value between -5 and +5) grow or shrink the ball. A match lasts 1 minute. The winner is decided by, in order: most kills, fewest deaths, largest ball.

User features: sign-up, login/logout, lobby creation and joining, and personal statistics (kills, deaths, wins, percentages).

## Architecture

```
Client ──► Central Node (Spring Boot) ◄──► MySQL
                │  (JInterface)
                ▼
        Supervisor (Erlang) ◄──► EGS 1..N (Erlang Game Server)
                                       ▲
Client ──────── WSS (WebSocket) ───────┘
```

| Component | Technology | Role |
|---|---|---|
| **Central Node** | Java, Spring Boot | Web pages, authentication, statistics, entry point to the Erlang cluster |
| **Database** | MySQL | `User` table (hashed passwords, statistics) |
| **Supervisor** | Erlang (rebar3, `gen_server`) | Dynamic EGS registration, load balancing (EGS with the fewest active games), auth token forwarding, stats collection, failure detection |
| **EGS** | Erlang (rebar3, Cowboy) | Real-time game logic, **authoritative** server: clients only send a direction, while positions and collisions are computed by the server |

### EGS internal processes
- **Local supervisor**: manages the lifecycle of game processes
- **Game process** (`gen_server`): state of a single match, tick every 50 ms, food spawn every 1 s
- **WebSocket handler**: one process per client, forwards inputs and updates
- **Fault manager**: heartbeats and leader election

### Join flow
1. The user clicks *JOIN*; the Java node asks the supervisor to authorize the client and generates a token.
2. The supervisor forwards the token to the EGS hosting the game.
3. The client receives IP, port, `gameId` and token in `game.html`, then connects via WSS by pressing *ENTER*.
4. The EGS compares the token sent by the client with the one from the supervisor: if they match, it replies `auth ok`.

## Fault tolerance

The supervisor is a single point of failure, mitigated with heartbeats and timeouts:

- Supervisor and EGSs exchange heartbeats every **1000 ms**; timeout is **3500 ms**.
- If an EGS stops responding, the supervisor removes it and notifies the others (its games are not recovered).
- If the supervisor crashes, each EGS **deterministically** elects (with no message exchange) the node with the **lowest IP**, which starts a temporary supervisor (`become_leader.sh`) and announces the new leader.
- On recovery, an admin restarts the original supervisor, passing the list of active EGSs; the temporary supervisor is then terminated.

**Assumptions:** reliable network (bounded delays, negligible packet loss) and no network partitions.

## Code structure

```
├── (Spring Boot)           Central Node
│   ├── config/             SecurityConfig, ErlangSupervisorConnectionConfig
│   ├── controller/         AuthController, LobbyController, PageController
│   ├── dto/  exception/  model/  repository/
│   ├── service/            AuthService, UserService, ErlangSupervisorConnectionService
│   ├── utils/              GenServerUtils
│   └── resources/          templates/ (HTML), static/ (css, js)
└── erl/
    ├── nodes_supervisor/   Cluster supervisor
    └── erlang_game_server/ EGS
        ├── egs_node_entry_point.erl     entry point (Cowboy + supervisor)
        ├── egs_supervisor.erl           local supervisor and game registry
        ├── egs_websocket_handler.erl    WebSocket handler
        ├── egs_game_module.erl          game logic (gen_server)
        ├── egs_game_module_utils.erl    physics, collisions, JSON encoding
        └── egs_fault_tolerance.erl      heartbeats and election
```

### Main endpoints (Central Node)
| Endpoint | Description |
|---|---|
| `POST /auth/signup` | Registration |
| `GET /lobby/create` | Create a lobby |
| `GET /lobby/join?lobbyId=<id>` | Request authorization to join |
| `GET /lobby/list` | List active lobbies |
| `/login`, `/home`, `/signup`, `/statistics`, `/join`, `/create`, `/game` | Web pages (protected ones redirect to login) |

Java ↔ Supervisor communication uses JInterface, emulating the `gen_server` protocol with messages shaped as `{type, request_id, {content}}` (`_req` / `_resp` suffixes) and Futures for the request-response mechanism.

## Client–server synchronization

- Time is divided into **ticks**; the server updates the state once per tick and broadcasts it to all clients.
- Clients send the **direction** (not the position): no impossible movements, and a lost update goes unnoticed.
- Centralizing the logic in the Erlang process guarantees consistent kills, scores and leaderboard.

## Deployment

The system runs on university VMs, reachable only via VPN.

| Component | IP |
|---|---|
| Central Java node | `10.2.1.13` |
| MySQL database | `10.2.1.12` |
| Erlang Supervisor | `10.2.1.11` |
| Erlang Game Servers | `10.2.1.4`, `10.2.1.5`, `10.2.1.6` |

## Running the system

Each VM has a startup script named `boot_node.sh`. **Startup order:**

1. Database and Java node (`10.2.1.12`, `10.2.1.13`)
2. Supervisor (`10.2.1.11`)
3. Game servers (`10.2.1.4`, `10.2.1.5`, `10.2.1.6`)

Build the Erlang components with `rebar3`; the Java node with Spring Boot (Maven/Gradle).

## Notes

The CSS styling and part of the client-side rendering (the player's ball) were developed with the support of generative AI tools. The WebSocket handler is based on an [Oxagile tutorial](https://www.oxagile.com/article/handlingwebsocket-connections-in-erlang-application/).
