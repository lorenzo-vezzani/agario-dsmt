package it.unipi.dsmt.controller;

import it.unipi.dsmt.dto.UserStatsDTO;
import it.unipi.dsmt.service.UserService;
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

    @GetMapping("/game")
    public String gamePage(
            Authentication authentication,
            @RequestParam String gameId,
            @RequestParam String hostIp,
            @RequestParam Integer hostPort,
            Model model
    ) {
        if (!(authentication != null && authentication.isAuthenticated() && !(authentication instanceof AnonymousAuthenticationToken))) {
            // user not authenticated
            return "redirect:/login";
        }

        model.addAttribute("gameId", gameId);
        model.addAttribute("hostIp", hostIp);
        model.addAttribute("hostPort", hostPort);
        model.addAttribute("playerId", authentication.getName());
        System.out.println("Player ID: " + authentication.getName());
        return "game";
    }
}
