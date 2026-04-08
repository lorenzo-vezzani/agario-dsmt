package it.unipi.dsmt.controller;

import it.unipi.dsmt.dto.UserStatsDTO;
import it.unipi.dsmt.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class PageController {

    private final UserService userService;

    public PageController(UserService userService) {
        this.userService = userService;
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
        return "home";
    }

    @GetMapping("/")
    public String root() {
        return "home";
    }

    @GetMapping("/signup")
    public String signup(Authentication authentication) {
        if (authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken)) {
            // user already authenticated
            return "redirect:/home";
        }

        return "signup";
    }

    @GetMapping("/statistics")
    public String signup(Authentication authentication, Model model) {
        if (authentication == null) {
            return "redirect:/login";
        }

        String username = authentication.getName();
        UserStatsDTO stats = userService.getUserStats(username);
        model.addAttribute("stats", stats);

        return "statistics";
    }

    @GetMapping("/join")
    public String servers(Authentication authentication) {
        if (authentication == null) {
            return "redirect:/login";
        }
        return "games_list";
    }

    @GetMapping("/create")
    public String create(Authentication authentication) {
        if (authentication == null) {
            return "redirect:/login";
        }
        return "new_game_server";
    }

    @GetMapping("/game")
    public String gamePage(
            Authentication authentication,
            HttpServletRequest request,
            @RequestParam String gameId,
            @RequestParam String hostIp,
            @RequestParam Integer hostPort,
            Model model
    ) {
        if (!(authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken))) {
            // user not authenticated
            return "redirect:/login";
        }

        HttpSession session = request.getSession(false);
        if (session == null) {
            // client not authenticated (but the request should be filtered before)
            return "redirect:/login";
        }
        String sessionId = session.getId();

        model.addAttribute("gameId", gameId);
        model.addAttribute("hostIp", hostIp);
        model.addAttribute("hostPort", hostPort);
        model.addAttribute("playerId", authentication.getName());
        model.addAttribute("gameToken", sessionId);
        System.out.println("Player ID: " + authentication.getName());
        return "game";
    }
}
