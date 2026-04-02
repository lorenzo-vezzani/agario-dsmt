package it.unipi.dsmt.service;

import it.unipi.dsmt.config.AgarioConfig;
import it.unipi.dsmt.model.GameInfo;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class LobbyService {

    private final AgarioConfig agarioConfig;
    // public record GameInfo(String gameId, String hostIp, int port) {}


    public LobbyService(AgarioConfig agarioConfig) {
        this.agarioConfig = agarioConfig;
    }

    public String startLobby() {
        return null;
    }

    public List<GameInfo> getLiveGames() {
        GameInfo g1 = new GameInfo("b", "0.0.0.0");
        GameInfo g2 = new GameInfo("c", "0.0.0.0");
        return List.of(g1, g2);
    }

    public String createGame() {
        return "todo";
    }
}
