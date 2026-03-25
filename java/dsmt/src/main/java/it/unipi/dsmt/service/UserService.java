package it.unipi.dsmt.service;

import it.unipi.dsmt.exception.UserNotFoundException;
import org.springframework.stereotype.Service;
import it.unipi.dsmt.model.User;
import it.unipi.dsmt.repository.UserRepository;

@Service
public class UserService {

    private final UserRepository repo;

    public UserService(UserRepository repo) {
        this.repo = repo;
    }

    public User getUserByUsername(String username) {
        User foundUser = repo.findById(username).orElse(null);
        if (foundUser == null) {
            throw new UserNotFoundException();
        }

        return foundUser;
    }
}