package it.unipi.dsmt.dto;

import java.time.LocalDateTime;

// record
public record UserStatsDTO (
    String username,
    String email,
    LocalDateTime createdAt,

    int gamesPlayed,
    int gamesWon,
    int gamesLost,
    int deaths,
    int dotsEaten,          // kills

    double winPercentage,
    double lossPercentage,
    double avgKillsPerGame,
    double avgDeathsPerGame
) {}
