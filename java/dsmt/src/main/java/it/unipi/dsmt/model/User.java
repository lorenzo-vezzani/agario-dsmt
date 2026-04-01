package it.unipi.dsmt.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "user")
public class User {

    @Id
    @Column(length = 50)
    private String username;

    @Column(length = 100, nullable = false, unique = true)
    private String email;

    @Column(length = 255, nullable = false)
    private String password;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "games_played", nullable = false)
    private int gamesPlayed;

    @Column(name = "games_won", nullable = false)
    private int gamesWon;

    @Column(name = "dots_eaten", nullable = false)
    private int dotsEaten;

    @Column(name = "deaths", nullable = false)
    private int deaths;


    // ---------- CONSTRUCTORS ---------- //
    public User() {}

    public User(String username, String email, String password, int gamesPlayed, int gamesWon, int dotsEaten, int deaths) {
        this.username = username;
        this.email = email;
        this.password = password;
        this.gamesPlayed = gamesPlayed;
        this.gamesWon = gamesWon;
        this.dotsEaten = dotsEaten;
        this.createdAt = LocalDateTime.now();
        this.deaths = deaths;
    }

    // ---------- GETTERS AND SETTERS ---------- //
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) {this.createdAt = createdAt;}

    public int getGamesPlayed() { return gamesPlayed; }
    public void setGamesPlayed(int gamesPlayed) { this.gamesPlayed = gamesPlayed; }

    public int getGamesWon() { return gamesWon; }
    public void setGamesWon(int gamesWon) { this.gamesWon = gamesWon; }

    public int getDotsEaten() { return dotsEaten; }
    public void setDotsEaten(int dotsEaten) { this.dotsEaten = dotsEaten; }

    public int getDeaths() {
        return deaths;
    }

    public void setDeaths(int deaths) {
        this.deaths = deaths;
    }
}