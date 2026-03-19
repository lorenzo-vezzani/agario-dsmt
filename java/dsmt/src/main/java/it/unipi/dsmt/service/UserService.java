package it.unipi.dsmt.service;

import it.unipi.dsmt.dto.RegisterRequestDTO;
import it.unipi.dsmt.exception.EmailAlreadyExistsException;
import it.unipi.dsmt.exception.UsernameAlreadyExistsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

import it.unipi.dsmt.model.User;
import it.unipi.dsmt.repository.UserRepository;

@Service
public class UserService {

    private final UserRepository repo;
    private final PasswordEncoder passwordEncoder;

    public UserService(UserRepository repo, PasswordEncoder passwordEncoder) {
        this.repo = repo;
        this.passwordEncoder = passwordEncoder;
    }

    public User createUser(RegisterRequestDTO dto) {
        // check if a user with the same email exists
        if (repo.existsByEmail(dto.getEmail())) {
            throw new EmailAlreadyExistsException();
        }

        // check if a user with the same username exists
        if (repo.existsByUsername(dto.getUsername())) {
            throw new UsernameAlreadyExistsException();
        }

        User user = new User();
        user.setUsername(dto.getUsername());
        user.setEmail(dto.getEmail());
        user.setPassword(passwordEncoder.encode(dto.getPassword()));
        user.setGamesPlayed(0);
        user.setGamesWon(0);
        user.setDotsEaten(0);
        user.setCreatedAt(LocalDateTime.now());
        return repo.save(user);
    }

    public User getUserByUsername(String username) {
        return repo.findById(username).orElse(null);
    }
}