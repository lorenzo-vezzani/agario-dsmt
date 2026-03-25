package it.unipi.dsmt.controller;

import it.unipi.dsmt.exception.EmailAlreadyExistsException;
import it.unipi.dsmt.exception.UsernameAlreadyExistsException;
import it.unipi.dsmt.service.AuthService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
@RequestMapping("/auth")
class AuthController {
    @Autowired
    AuthService authService;

    @PostMapping("/signup")
    public String signup(@RequestParam("username") String username, @RequestParam("email") String email, @RequestParam("password") String password, Model model) {
        try {
            authService.signup(username, email, password);
        } catch (UsernameAlreadyExistsException e) {
            model.addAttribute("error", "Username già esistente!");
            return "signup";
        }
        catch (EmailAlreadyExistsException e) {
            model.addAttribute("error", "Email già esistente!");
            return "signup";
        }
        return "redirect:/login";
    }
}
