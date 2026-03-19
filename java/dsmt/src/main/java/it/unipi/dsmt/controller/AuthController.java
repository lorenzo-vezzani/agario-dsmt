package it.unipi.dsmt.controller;

import it.unipi.dsmt.dto.LoginRequestDTO;
import it.unipi.dsmt.dto.LoginResponseDTO;
import it.unipi.dsmt.dto.RegisterRequestDTO;
import it.unipi.dsmt.dto.RegisterResponseDTO;
import it.unipi.dsmt.model.User;
import it.unipi.dsmt.service.AuthService;
import it.unipi.dsmt.service.JwtService;
import it.unipi.dsmt.service.UserService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
@RequestMapping("/auth")
class AuthController {
    private final UserService service;
    private final AuthService authService;
    private final JwtService jwtService;

    public AuthController(UserService service, AuthService authService, JwtService jwtService) {
        this.service = service;
        this.authService = authService;
        this.jwtService = jwtService;
    }

    @PostMapping("/register")
    public ResponseEntity<RegisterResponseDTO> createUser(@Valid @RequestBody RegisterRequestDTO dto) {
        User savedUser = service.createUser(dto);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(new RegisterResponseDTO("ok", savedUser.getUsername()));
    }

    @PostMapping("/login")
    public ResponseEntity<LoginResponseDTO> login(@Valid @RequestBody LoginRequestDTO dto) {
        authService.authUser(dto);
        return ResponseEntity
                .status(HttpStatus.OK)
                .body(new LoginResponseDTO("ok", jwtService.generateToken(dto.getUsername())));
    }
}
