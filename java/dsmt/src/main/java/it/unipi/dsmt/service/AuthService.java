package it.unipi.dsmt.service;

import it.unipi.dsmt.dto.LoginRequestDTO;
import it.unipi.dsmt.exception.IncorrectPasswordException;
import it.unipi.dsmt.exception.UserNotFoundException;
import it.unipi.dsmt.model.User;
import it.unipi.dsmt.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {
    private final UserRepository repo;
    private final PasswordEncoder passwordEncoder;

    public AuthService(UserRepository repo, PasswordEncoder passwordEncoder) {
        this.repo = repo;
        this.passwordEncoder = passwordEncoder;
    }

    public void authUser(LoginRequestDTO dto) {
        // retrieve user with the given username
        User foundUser = repo.findByUsername(dto.getUsername());
        if (foundUser == null) {
            throw new UserNotFoundException();
        }

        // check password
        if (!passwordEncoder.matches(dto.getPassword(), foundUser.getPassword())) {
            throw new IncorrectPasswordException();
        }

        // if we make it here, the authentication is complete
    }
}
