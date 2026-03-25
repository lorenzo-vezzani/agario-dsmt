package it.unipi.dsmt.service;

import it.unipi.dsmt.config.AgarioConfig;
import org.springframework.stereotype.Service;

@Service
public class LobbyService {

    private final AgarioConfig agarioConfig;

    public LobbyService(AgarioConfig agarioConfig) {
        this.agarioConfig = agarioConfig;
    }

    public String startLobby() {
        return null;
    }
}
