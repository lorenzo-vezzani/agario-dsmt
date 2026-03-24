# EGS — Erlang Game Server

Un game server real-time per giochi multiplayer arena (stile *agar.io*), scritto in Erlang/OTP con [Cowboy](https://github.com/ninenines/cowboy) come layer HTTP/WebSocket.

---

## Indice

1. [Avvio rapido](#1-avvio-rapido)
2. [Integrazione WebSocket — guida per il web developer](#2-integrazione-websocket--guida-per-il-web-developer)
3. [Struttura dei file sorgente](#3-struttura-dei-file-sorgente)
4. [Architettura a runtime](#4-architettura-a-runtime)
5. [Messaggi interni tra processi](#5-messaggi-interni-tra-processi)
6. [Costanti di gioco](#6-costanti-di-gioco)

---

## 1. Avvio rapido

```bash
# Compilare e avviare l'applicazione OTP
rebar3 shell
```

Il server si mette in ascolto sulla porta **49153** (TCP, HTTP/WebSocket).

Per creare una partita prima che un client possa connettersi, dalla shell Erlang:

```erlang
egs_supervisor:start_game(<<"game-1">>).
```

Altri comandi utili:
```erlang
%% number of running games
egs_supervisor:game_count().

%% list all games with their pids
egs_supervisor:list_games().

%% stop a game
egs_supervisor:stop_game(<<"game-1">>).
```

---

## 2. Integrazione WebSocket — guida per il web developer

### 2.1 URL di connessione

```
ws://<host>:49153/ws/<game_id>/<player_id>
```

| Segmento    | Tipo   | Descrizione                                        |
|-------------|--------|----------------------------------------------------|
| `game_id`   | stringa | Identificatore della partita, es. `game-1`        |
| `player_id` | stringa | Nome/identificatore del giocatore, es. `alice`    |

Esempio completo: `ws://localhost:49153/ws/game-1/alice`

> **Nota:** `game_id` e `player_id` vengono trasmessi come segmenti di path URL, non come query string o header.

### 2.2 Handshake e gestione degli errori di connessione

La connessione avviene in due fasi:

1. **HTTP Upgrade** — Cowboy riceve la richiesta HTTP e la converte in WebSocket.
2. **Registrazione al game process** — `websocket_init` chiama `egs_game_module:join/2`. Se la partita non esiste, il server chiude immediatamente il WebSocket con:

```
Close frame — codice 1008, motivo: "game_not_found"
```

Il client deve gestire questo caso e mostrare un errore all'utente prima che arrivi qualsiasi frame dati.

### 2.3 Messaggi server → client (game state)

Il server invia un frame di testo JSON ogni **20 ms** (tick rate fisso). Il payload descrive l'intera arena in quel momento.

**Formato:**

```json
{
  "balls": [
    { "id": "alice", "x": 312.45, "y": 874.10, "r": 20 },
    { "id": "bob",   "x": 1540.00, "y": 220.30, "r": 20 }
  ]
}
```

| Campo      | Tipo    | Descrizione                                              |
|------------|---------|----------------------------------------------------------|
| `balls`    | array   | Lista di tutte le palline presenti nell'arena in quel tick |
| `id`       | stringa | `player_id` del giocatore che controlla questa pallina  |
| `x`        | float   | Posizione orizzontale nell'arena, in unità arena [0–2000] |
| `y`        | float   | Posizione verticale nell'arena, in unità arena [0–2000]  |
| `r`        | intero  | Raggio della pallina in unità arena (attualmente sempre 20) |

**Coordinate:** l'origine `(0, 0)` è in alto a sinistra. L'asse Y cresce verso il basso (convenzione standard schermo).

**Frequenza:** il server invia lo stato solo se c'è almeno un client connesso alla partita. Il client deve aggiornare il render ad ogni messaggio ricevuto.

### 2.4 Messaggi client → server (aggiornamento direzione)

Il client deve inviare un frame di testo JSON con la direzione di movimento desiderata.

**Formato:**

```json
{ "dx": 0.7071, "dy": -0.7071 }
```

| Campo | Tipo  | Range    | Descrizione                                  |
|-------|-------|----------|----------------------------------------------|
| `dx`  | float | [-1, +1] | Componente orizzontale del vettore direzione |
| `dy`  | float | [-1, +1] | Componente verticale del vettore direzione   |

**Vincoli sul vettore:**
- Il vettore **deve essere normalizzato** (lunghezza = 1.0). Il server moltiplica direttamente `dx` e `dy` per la velocità costante `SPEED = 3.0` unità/tick — non normalizza lato server.
- Per fermare la pallina, inviare `{"dx": 0, "dy": 0}`.

**Calcolo consigliato lato client:**

```javascript
// Dato mouse (mx, my) e posizione della propria pallina (bx, by) in coordinate arena
const vx = mx - bx;
const vy = my - by;
const len = Math.hypot(vx, vy);
const dx = len > 0.5 ? vx / len : 0;
const dy = len > 0.5 ? vy / len : 0;
ws.send(`{"dx":${dx.toFixed(4)},"dy":${dy.toFixed(4)}}`);
```

**Frequenza di invio consigliata:** 20 ms (allineata al tick del server). Inviare più frequentemente non porta benefici poiché il server applica la direzione una volta per tick.

**Parsing lato server:** il server usa regex su `"dx":<float>` e `"dy":<float>`. Il JSON deve essere in formato compatto. Valori non validi vengono silenziosamente ignorati (la pallina mantiene la direzione precedente).

### 2.5 Disconnessione

Quando il client chiude il WebSocket (normalmente o per crash), il server rimuove automaticamente il giocatore dalla partita e dalla lista delle palline trasmesse nei tick successivi.

Il client non deve inviare nessun messaggio esplicito di "leave": basta chiudere la connessione.

---

## 3. Struttura dei file sorgente

```
egs/
├── egs_app.src                  # Descrittore applicazione OTP
├── egs_node_entry_point.erl     # Entry point: avvia Cowboy e il supervisor radice
├── egs_supervisor.erl           # Supervisor + registry ETS
├── egs_game_module.erl          # Logica di una singola partita (gen_server)
├── egs_game_module_utils.erl    # Funzioni pure: fisica, collisioni, encode/decode JSON
└── egs_websocket_handler.erl    # Handler WebSocket Cowboy (un processo per client)
```

### `egs_app.src` — Descrittore OTP

File di configurazione dell'applicazione OTP (`{application, egs, [...]}`). Dichiara le dipendenze (`cowboy`, `ranch`), la versione e il modulo di avvio (`egs_node_entry_point`). Non contiene logica.

### `egs_node_entry_point.erl` — Entry point

Behaviour: `application`.

Avviato automaticamente da OTP. Responsabilità:
- Compila la routing table Cowboy: mappa `/ws/:game_id/:player_id` → `egs_websocket_handler`.
- Avvia il listener HTTP/WebSocket sulla porta 49153 con `cowboy:start_clear/3`.
- Avvia il supervisor `egs_supervisor`.

In `stop/1` ferma il listener Cowboy (tutte le connessioni WebSocket vengono chiuse).

### `egs_supervisor.erl` — Supervisor delle partite e registry

Behaviour: `supervisor`.

Doppio ruolo:

**supervisor:** strategia **`simple_one_for_one`** con figli `temporary` (non riavviati in caso di crash). Tutti i processi-partita condividono la stessa spec: `egs_game_module:start_link/1`. Nuovi figli aggiunti dinamicamente tramite `supervisor:start_child/2`.

**registry:** mantiene una tabella ETS named `game_proc_table` con coppie `{GameId, Pid}`. La tabella è `public` — i processi-partita possono scriverci direttamente. Espone:

| Funzione              | Descrizione                                     |
|-----------------------|-------------------------------------------------|
| `start_game/1`        | Avvia un nuovo processo-partita con dato GameId |
| `stop_game/1`         | Termina la partita e rimuove dal registry       |
| `lookup/1`            | Ritorna `{ok, Pid}` o `{error, not_found}`      |
| `register_game/2`     | Inserisce `{GameId, Pid}` nell'ETS (chiamato da init delle partite) |
| `unregister_game/1`   | Rimuove dal registry (chiamato da terminate delle partite) |
| `list_games/0`        | Lista tutti i `{GameId, Pid}` attivi            |
| `game_count/0`        | Numero di partite attive                        |

### `egs_game_module.erl` — Logica di una partita

Behaviour: `gen_server`.

Un processo per partita. Stato interno:

```erlang
#{
  game_id => binary(),         % identificatore della partita
  clients => #{pid() => binary()},  % WsPid → PlayerId
  balls   => #{binary() => map()}   % PlayerId → Ball#{x,y,dx,dy,radius}
}
```

Ciclo di vita:
- **`init/1`**: registra il proprio PID nell'ETS tramite `egs_supervisor:register_game/2`, schedula il primo tick con `erlang:send_after/3`.
- **`terminate/2`**: chiama `egs_supervisor:unregister_game/1` per pulire il registry.

Cast gestiti (messaggi asincroni):

| Cast                          | Effetto                                                             |
|-------------------------------|---------------------------------------------------------------------|
| `{join, WsPid, PlayerId}`     | Monitora WsPid, crea una pallina casuale, aggiorna entrambe le mappe |
| `{leave, WsPid, PlayerId}`    | Rimuove giocatore da `clients` e `balls`                           |
| `{player_msg, PlayerId, Msg}` | Decodifica il JSON di direzione, aggiorna `dx`/`dy` della pallina  |

Info gestite (messaggi di sistema):

| Info                                 | Effetto                                                        |
|--------------------------------------|----------------------------------------------------------------|
| `tick`                               | Muove le palline, controlla collisioni, broadcast stato JSON, reschedula tick |
| `{'DOWN', _, process, WsPid, _}`     | Rimozione automatica del giocatore se il WS handler crasha     |

### `egs_game_module_utils.erl` — Funzioni di gioco

Modulo di funzioni pure (nessuno stato, nessun processo). Contiene tutta la fisica e la serializzazione.

| Funzione                      | Descrizione                                                         |
|-------------------------------|---------------------------------------------------------------------|
| `gl__spawn_random_ball/0`     | Crea una pallina con posizione casuale in [0, 2000]², `dx=dy=0.0`, `radius=20.0` |
| `gl__move_balls/1`            | Applica `gl__move_ball_single` a ogni pallina nella mappa           |
| `gl__move_ball_single/1`      | `x += dx * SPEED`, `y += dy * SPEED`, con clamp ai bordi dell'arena |
| `gl__handle_balls_collisions/1` | Controlla tutte le coppie di palline per collisioni (placeholder, non produce effetti) |
| `decode__direction_update/1`  | Parsa `{"dx":…,"dy":…}` via regex, ritorna `{ok, Dx, Dy}` o `error` |
| `encode__state/1`             | Serializza la mappa `balls` nel JSON di stato da inviare ai client  |

### `egs_websocket_handler.erl` — Handler WebSocket

Un processo Cowboy per ogni client connesso. Non è un `gen_server` ma un processo Cowboy gestito dal framework. Stato interno: `#{game_id, player_id}`.

| Callback             | Quando viene chiamato                          | Cosa fa                                              |
|----------------------|------------------------------------------------|------------------------------------------------------|
| `init/2`             | HTTP request in arrivo                         | Estrae `game_id`/`player_id` dal path, triggera upgrade a WS |
| `websocket_init/1`   | Upgrade WS completato                          | Chiama `egs_game_module:join/2`; se la partita non esiste, chiude con `1008` |
| `websocket_handle/2` | Frame di testo dal browser                     | Inoltro grezzo a `egs_game_module:player_msg/3`      |
| `websocket_info/2`   | Messaggio `{game_state, Payload}` dal game process | Invia il payload come frame di testo al browser   |
| `terminate/3`        | Connessione chiusa (qualsiasi motivo)          | Chiama `egs_game_module:leave/2` per pulizia         |

---

## 4. Architettura a runtime

### Albero di supervisione

```
[OTP Application: egs]
└── egs_node_entry_point  (application callback — non è un processo supervisionato)
    ├── cowboy listener :ws_list  (porta 49153 — supervisione interna Cowboy/Ranch)
    │   └── egs_websocket_handler  (un processo per client WebSocket connesso)
    └── egs_supervisor  (supervisor, simple_one_for_one + ETS registry)
        ├── egs_game_module [<<"game-1">>]  (gen_server, temporary)
        ├── egs_game_module [<<"game-2">>]  (gen_server, temporary)
        └── ...
```

### Processi a runtime per ogni client connesso

Quando un browser si connette a `ws://host/ws/game-1/alice`:

```
Browser
  │  WebSocket
  ▼
egs_websocket_handler (processo Cowboy, pid: WsPid)
  │  gen_server:cast  →  {join, WsPid, <<"alice">>}
  │  gen_server:cast  →  {player_msg, <<"alice">>, Msg}   (ogni frame ricevuto)
  │  gen_server:cast  →  {leave, WsPid, <<"alice">>}      (alla disconnessione)
  ▼
egs_game_module [<<"game-1">>] (gen_server, pid: GamePid)
  │  erlang:send  →  {game_state, JSON}   (ogni tick, 50 Hz)
  ▼
egs_websocket_handler  →  frame WebSocket  →  Browser
```

### Lookup del processo-partita

Ogni volta che `egs_websocket_handler` o `egs_game_module` ha bisogno di trovare il PID di una partita, esegue una lettura dalla tabella ETS:

```
egs_supervisor:lookup(<<"game-1">>)
  → ets:lookup(game_proc_table, <<"game-1">>)
  → [{<<"game-1">>, <0.123.0>}]
  → {ok, <0.123.0>}
```

Questo è thread-safe: le letture ETS sono concorrenti senza lock.

### Monitoring dei WebSocket handler

Quando un giocatore entra, `egs_game_module` esegue `monitor(process, WsPid)`. Se il browser si disconnette bruscamente (senza chiamare `leave/2`), il processo WS handler muore e il game process riceve automaticamente:

```erlang
{'DOWN', Ref, process, WsPid, Reason}
```

Il game process reagisce rimuovendo il giocatore dalla partita senza nessun intervento esterno.

---

## 5. Messaggi interni tra processi

### Da `egs_websocket_handler` → `egs_game_module`

Tutti via `gen_server:cast` (asincroni, non bloccanti).

```erlang
% Nuovo giocatore (chiamato da websocket_init)
gen_server:cast(GamePid, {join, WsPid, PlayerId})

% Messaggio di direzione dal browser (chiamato da websocket_handle)
gen_server:cast(GamePid, {player_msg, PlayerId, RawBinary})

% Giocatore uscito (chiamato da terminate)
gen_server:cast(GamePid, {leave, WsPid, PlayerId})
```

### Da `egs_game_module` → `egs_websocket_handler`

Via `erlang:send` diretto (il PID è noto dalla mappa `clients`).

```erlang
% Broadcast su ogni tick (50 Hz)
WsPid ! {game_state, JsonBinary}
```

### Messaggi interni al `egs_game_module`

```erlang
% Auto-schedulato ogni 20 ms con erlang:send_after
self() ! tick

% Ricevuto dal runtime Erlang quando un processo monitorato muore
{'DOWN', MonitorRef, process, DeadWsPid, Reason}
```

### Messaggi `egs_supervisor` ↔ `egs_game_module`

La comunicazione avviene tramite ETS (non messaggi), eccetto durante la supervisione OTP standard (`supervisor:start_child`, `supervisor:terminate_child`).

---

## 6. Costanti di gioco

Definite come macro in `egs_game_module_utils.erl`:

| Costante   | Valore     | Descrizione                                     |
|------------|------------|-------------------------------------------------|
| `ARENA_W`  | `2000.0`   | Larghezza arena in unità logiche                |
| `ARENA_H`  | `2000.0`   | Altezza arena in unità logiche                  |
| `BALL_R`   | `20.0`     | Raggio iniziale di ogni pallina                 |
| `SPEED`    | `3.0`      | Unità percorse per tick nella direzione `(dx,dy)` |
| `TICK_MS`  | `20`       | Intervallo tra tick in millisecondi (50 Hz) — in `egs_game_module.erl` |

Il clamp di posizione mantiene il **centro** della pallina dentro i bordi (non il bordo della pallina stessa). Per aggiungere il clamp corretto al raggio: `clamp(x, Ball.r, ARENA_W - Ball.r)`.

---

## Appendice: flusso completo di una connessione

```
1. Browser apre  ws://host:49153/ws/game-1/alice
2. Cowboy chiama egs_websocket_handler:init/2
   → estrae game_id=<<"game-1">>, player_id=<<"alice">>
   → restituisce {cowboy_websocket, Req, State}
3. Cowboy completa l'upgrade HTTP → WS
4. Cowboy chiama egs_websocket_handler:websocket_init/1
   → egs_game_module:join(<<"game-1">>, <<"alice">>)
   → lookup ETS: trova GamePid
   → gen_server:cast(GamePid, {join, self(), <<"alice">>})
5. egs_game_module riceve {join, WsPid, <<"alice">>}
   → monitor(process, WsPid)
   → crea pallina casuale
   → aggiorna clients e balls
6. Ogni 20 ms: egs_game_module riceve tick
   → muove palline
   → WsPid ! {game_state, <<"{\"balls\":[...]}">>}
7. egs_websocket_handler riceve {game_state, Payload}
   → {reply, {text, Payload}, State}  →  frame WS  →  Browser
8. Browser invia {"dx":0.71,"dy":-0.56}
   → websocket_handle → gen_server:cast(GamePid, {player_msg, ...})
   → aggiorna dx,dy della pallina <<"alice">>
9. Browser chiude tab
   → egs_websocket_handler:terminate/3
   → egs_game_module:leave(<<"game-1">>, <<"alice">>)
   → gen_server:cast(GamePid, {leave, WsPid, <<"alice">>})
   → rimozione da clients e balls
```

