# Springboot node
## Endpoints
### Web pages endpoints
- /login -> login.html (pagina per fare il login)
- /signup -> signup.html (pagina per registrarsi)
- /, /home -> home.html (pagina dove si finisce dopo il login, si sceglie se creare una nuova partita o partecipare ad una esistente)
- /join -> game_servers.html (pagina dove si sceglie a quale game server esistente connettersi)
- /create -> new_game_server.html (pagina dove si crea un nuovo game server)
- /game -> game.html (pagina dove ci si connette al game server e si gioca)

### REST API endpoints
- /auth/login -> dove si mandano i dati per fare il login
- /auth/signup -> dove si mandano i dati per fare la registrazione
- /lobby/create -> si richiede un nuovo gameserver e restituisce i dettagli di quest'ultimo
- /lobby/join?lobbyId=<id della lobby> -> si richiede l'autorizzazione all'accesso di un game server esistente
- /lobby/list -> si richiede la lista dei game server esistenti