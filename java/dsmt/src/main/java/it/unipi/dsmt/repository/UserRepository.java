package it.unipi.dsmt.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import it.unipi.dsmt.model.User;

public interface UserRepository extends JpaRepository<User, String> {

    User findByEmail(String email);

    User findByUsername(String username);

    boolean existsByEmail(String email);

    boolean existsByUsername(String username);
}