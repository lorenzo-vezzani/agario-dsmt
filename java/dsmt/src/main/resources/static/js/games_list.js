async function startListUpdate() {
    await listUpdate();
    setInterval(listUpdate, 10000);
}

async function listUpdate() {
    try {
        const response = await fetch('/lobby/list', {
            method: 'GET'
        });

        let tbody = document.getElementById("server-list");
        while (tbody.firstChild) {
            tbody.removeChild(tbody.firstChild);
        }

        if (response.status !== 200) {
            let row = document.createElement("tr");
            let cell = document.createElement("td");
            cell.innerText = "Error trying to get active servers"
            cell.colSpan = 3;
            row.appendChild(cell)
            tbody.appendChild(row);
            return;
        }

        const data = await response.json();

        if (data.length === 0) {
            let row = document.createElement("tr");
            let cell = document.createElement("td");
            cell.innerText = "No active servers found"
            cell.colSpan = 3;
            row.appendChild(cell)
            tbody.appendChild(row);
            return;
        }

        for (let serverInfo of data) {
            let row = document.createElement("tr");
            let gameId = document.createElement("td");
            let server = document.createElement("td");
            let players = document.createElement("td");
            let join = document.createElement("td");
            let joinButton = document.createElement("button");

            gameId.innerText = serverInfo.lobbyId.slice(0, 16) + '…';
            gameId.title = serverInfo.lobbyId;
            server.innerText = `${serverInfo.lobbyIp}:${serverInfo.lobbyPort}`;
            players.innerText = serverInfo.lobbyPlayers;
            joinButton.innerText = "Join";
            joinButton.classList.add("btn");
            joinButton.addEventListener("click", async () => {
                // ask permission
                const permParams = new URLSearchParams({
                    lobbyId: serverInfo.lobbyId
                });
                const resp = await fetch('/lobby/join?' + permParams, {
                    method: 'GET'
                });
                if (resp.status !== 200) {
                    joinButton.innerText = "Can't join this game";
                    joinButton.disabled = true;
                    return;
                }

                const params = new URLSearchParams({
                    gameId: serverInfo.lobbyId,
                    hostIp: serverInfo.lobbyIp,
                    hostPort: serverInfo.lobbyPort
                });
                window.location.href = "/game?" + params;
            });
            join.appendChild(joinButton);

            row.appendChild(gameId);
            row.appendChild(server);
            row.appendChild(players);
            row.appendChild(join);
            tbody.appendChild(row);
        }
    } catch (error) {
        console.error('Errore:', error);
    }
}