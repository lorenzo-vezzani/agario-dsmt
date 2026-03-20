package it.unipi.dsmt.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDateTime;

public class GetUserResponseDTO {

    @NotBlank
    private String username;

    @NotBlank
    private LocalDateTime createdAt;

    @NotNull
    private int gamesPlayed;

    @NotNull
    private int gamesWon;

    @NotNull
    private int dotsEaten;

    public GetUserResponseDTO(String username, LocalDateTime createdAt, int gamesPlayed, int gamesWon, int dotsEaten) {
        this.username = username;
        this.createdAt = createdAt;
        this.gamesPlayed = gamesPlayed;
        this.gamesWon = gamesWon;
        this.dotsEaten = dotsEaten;
    }

    public int getDotsEaten() {
        return dotsEaten;
    }

    public void setDotsEaten(int dotsEaten) {
        this.dotsEaten = dotsEaten;
    }

    public int getGamesWon() {
        return gamesWon;
    }

    public void setGamesWon(int gamesWon) {
        this.gamesWon = gamesWon;
    }

    public int getGamesPlayed() {
        return gamesPlayed;
    }

    public void setGamesPlayed(int gamesPlayed) {
        this.gamesPlayed = gamesPlayed;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }
}
