async function createGameServer() {
    let messageBox = document.getElementById("message");

    const response = await fetch('/lobby/create', {
        method: 'GET'
    });

    if (response.status !== 200) {
        messageBox.innerText = "Error while creating the game server!";
        return;
    }

    const data = await response.json();

    // ask permission
    const permParams = new URLSearchParams({
        lobbyId: data.lobbyId
    });
    const resp = await fetch('/lobby/join?' + permParams, {
        method: 'GET'
    });
    if (resp.status !== 200) {
        messageBox.innerText = "Can't join the new server!";
        return;
    }

    const params = new URLSearchParams({
        gameId: data.lobbyId,
        hostIp: data.lobbyIp,
        hostPort: data.lobbyPort
    });
    window.location.href = "/game?" + params;
}