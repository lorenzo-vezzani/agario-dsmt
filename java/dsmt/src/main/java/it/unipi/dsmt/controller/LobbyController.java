package it.unipi.dsmt.controller;

import it.unipi.dsmt.service.LobbyService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/lobby")
class LobbyController {

    private final LobbyService lobbyService;

    public LobbyController(LobbyService lobbyService) {
        this.lobbyService = lobbyService;
    }

    @GetMapping("/start")
    public ResponseEntity<?> startLobby() {
        // TODO implement
        return ResponseEntity
                .status(HttpStatus.OK)
                .body(lobbyService.startLobby());
    }

    @GetMapping("/join")
    public ResponseEntity<?> joinLobby() {
        // TODO implement
        return null;
    }
}
