package it.unipi.dsmt.controller;

import it.unipi.dsmt.dto.GetUserResponseDTO;
import it.unipi.dsmt.dto.LoginResponseDTO;
import org.jetbrains.annotations.NotNull;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import it.unipi.dsmt.model.User;
import it.unipi.dsmt.service.UserService;

@RestController
@RequestMapping("/user")
public class UserController {

    private final UserService service;

    public UserController(UserService service) {
        this.service = service;
    }

    @GetMapping("/{username}")
    public ResponseEntity<@NotNull GetUserResponseDTO> getUser(@PathVariable String username) {
        User user = service.getUserByUsername(username);
        return ResponseEntity
                .status(HttpStatus.OK)
                .body(new GetUserResponseDTO(
                        user.getUsername(),
                        user.getCreatedAt(),
                        user.getGamesPlayed(),
                        user.getGamesWon(),
                        user.getDotsEaten())
                );
    }
}