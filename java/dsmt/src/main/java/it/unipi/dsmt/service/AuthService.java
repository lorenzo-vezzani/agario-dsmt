package it.unipi.dsmt.service;

import it.unipi.dsmt.exception.EmailAlreadyExistsException;
import it.unipi.dsmt.exception.InvalidEmailException;
import it.unipi.dsmt.exception.UsernameAlreadyExistsException;
import it.unipi.dsmt.model.User;
import it.unipi.dsmt.repository.UserRepository;
import jakarta.transaction.Transactional;
import org.jetbrains.annotations.NotNull;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@Service
public class AuthService implements UserDetailsService {
    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;


    @Override
    public @NotNull UserDetails loadUserByUsername(@NotNull String username) throws UsernameNotFoundException {
        User user = userRepository.findByUsername(username);
        if (user == null) {
            throw new UsernameNotFoundException(username);
        }

        // conversion to UserDetails for automatic authentication
        return org.springframework.security.core.userdetails.User.builder()
                .username(user.getUsername())
                .password(user.getPassword())
                .roles("USER")
                .build();
    }

    @Transactional
    public void signup(String username, String email, String password) {
        String regex = "^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$";
        if (!email.matches(regex)) {
            // invalid email
            throw new InvalidEmailException();
        }
        if (userRepository.existsByUsername(username)) {
            // username already used
            throw new UsernameAlreadyExistsException();
        }
        if (userRepository.existsByEmail(email)) {
            // email already used
            throw new EmailAlreadyExistsException();
        }

        // crea utente e salva password codificata
        User user = new User();
        user.setUsername(username);
        user.setEmail(email);
        user.setPassword(passwordEncoder.encode(password));
        user.setGamesPlayed(0);
        user.setGamesWon(0);
        user.setDotsEaten(0);
        user.setCreatedAt(LocalDateTime.now());
        userRepository.save(user);

        System.out.println("SALVATO");

        // redirect al login

    }
}
