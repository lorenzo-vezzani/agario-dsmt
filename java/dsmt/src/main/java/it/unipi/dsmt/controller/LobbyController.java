package it.unipi.dsmt.controller;

import it.unipi.dsmt.dto.LobbyInfoDTO;
import it.unipi.dsmt.service.ErlangSupervisorConnectionService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.constraints.NotEmpty;
import org.jetbrains.annotations.NotNull;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/lobby")
class LobbyController {

    @Autowired
    private ErlangSupervisorConnectionService supervisorConnectionService;

    @GetMapping("/create")
    public ResponseEntity<@NotNull LobbyInfoDTO> createLobby() {
        LobbyInfoDTO lobby = supervisorConnectionService.sendCreateLobbyRequest();
        if (lobby == null) {
            // an error occurred
            return ResponseEntity
                    .status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }

        return ResponseEntity
                .status(HttpStatus.OK)
                .body(lobby);
    }

    @GetMapping("/join")
    public ResponseEntity<@NotNull LobbyInfoDTO> joinLobby(HttpServletRequest request,
                                                           Authentication authentication,
                                                           @RequestParam @NotEmpty String lobbyId) {
        HttpSession session = request.getSession(false);
        UserDetails userDetails = ((UserDetails) authentication.getPrincipal());
        if (session == null || userDetails == null) {
            // client not authenticated (but the request should be filtered before)
            return ResponseEntity
                    .status(HttpStatus.UNAUTHORIZED)
                    .build();
        }
        String sessionId = session.getId();
        String username = userDetails.getUsername();

        boolean authorized = supervisorConnectionService.sendJoinLobbyRequest(username, lobbyId, sessionId);
        HttpStatus status = authorized ? HttpStatus.OK : HttpStatus.INTERNAL_SERVER_ERROR;
        return ResponseEntity
                .status(status)
                .build();
    }

    @GetMapping("/list")
    public ResponseEntity<@NotNull List<LobbyInfoDTO>> listLobby() {
        List<LobbyInfoDTO> lobbies = supervisorConnectionService.sendListLobbyRequest();
        if (lobbies == null) {
            return ResponseEntity
                    .status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .build();
        }

        return ResponseEntity
                .status(HttpStatus.OK)
                .body(lobbies);
    }
}
