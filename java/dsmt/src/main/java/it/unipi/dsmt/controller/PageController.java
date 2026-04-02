package it.unipi.dsmt.controller;

import it.unipi.dsmt.model.GameInfo;
import it.unipi.dsmt.service.LobbyService;
import org.jetbrains.annotations.NotNull;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

@Controller
public class PageController {

    private final LobbyService lobbyService;

    public PageController(LobbyService lobbyService) {
        this.lobbyService = lobbyService;
    }

    @GetMapping("/lobby")
    public String lobby(Authentication authentication, Model model) {

        if (!(authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken))) {
            // user not authenticated
            return "redirect:/login";
        }

        List<GameInfo> liveGames = lobbyService.getLiveGames();
        System.out.println("Live Games: " + liveGames);
        model.addAttribute("games", liveGames); // List<GameInfo>

        return "lobby";
    }

    @GetMapping("/game")
    public String gamePage(
            Authentication authentication,
            @RequestParam String gameId,
            @RequestParam String hostIp,
            Model model
    ) {
        if (!(authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken))) {
            // user not authenticated
            return "redirect:/login";
        }

        model.addAttribute("gameId", gameId);
        System.out.println("Game ID: " + gameId);
        model.addAttribute("hostIp", hostIp);
        System.out.println("Game IP: " + hostIp);
        model.addAttribute("playerId", authentication.getName());
        System.out.println("Player ID: " + authentication.getName());
        return "game"; // → templates/game.html
    }

    @PostMapping("/game/new")
    public String newGame() {
        String newId = lobbyService.createGame();
        return "redirect:/lobby?created=" + newId;
    }

    @GetMapping("/login")
    public String login(Authentication authentication) {
        if (authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken)) {
            // user already authenticated
            return "redirect:/home";
        }
        return "login";
    }

    @GetMapping("/home")
    public String home() {
        return "lobby";
    }

    @GetMapping("/signup")
    public String signup(Authentication authentication) {
        if (authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken)) {
            // user already authenticated
            return "redirect:/home";
        }

        return "signup";
    }
}
