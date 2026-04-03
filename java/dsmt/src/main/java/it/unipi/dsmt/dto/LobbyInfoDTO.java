package it.unipi.dsmt.dto;

import jakarta.validation.constraints.NotBlank;

public class LobbyInfoDTO {

    @NotBlank
    private String lobbyIp;

    private int lobbyPort;

    @NotBlank
    private String lobbyId;

    private int lobbyPlayers;

    public LobbyInfoDTO(String lobbyIp, int lobbyPort, String lobbyId,  int lobbyPlayers) {
        this.lobbyIp = lobbyIp;
        this.lobbyPort = lobbyPort;
        this.lobbyId = lobbyId;
        this.lobbyPlayers = lobbyPlayers;
    }

    public String getLobbyIp() {
        return lobbyIp;
    }

    public void setLobbyIp(String lobbyIp) {
        this.lobbyIp = lobbyIp;
    }

    public int getLobbyPort() {
        return lobbyPort;
    }

    public void setLobbyPort(int lobbyPort) {
        this.lobbyPort = lobbyPort;
    }

    public String getLobbyId() {
        return lobbyId;
    }

    public void setLobbyId(String lobbyId) {
        this.lobbyId = lobbyId;
    }

    public int getLobbyPlayers() {
        return lobbyPlayers;
    }

    public void setLobbyPlayers(int lobbyPlayers) {
        this.lobbyPlayers = lobbyPlayers;
    }
}
