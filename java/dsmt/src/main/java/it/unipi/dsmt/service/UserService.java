package it.unipi.dsmt.service;

import it.unipi.dsmt.dto.UserStatsDTO;
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

    public void updateUserStats(String username, boolean isUserWinner, int dotsEaten, int deaths) {
        User foundUser = getUserByUsername(username);

        foundUser.setGamesPlayed(foundUser.getGamesPlayed() + 1);
        if (isUserWinner) {
            foundUser.setGamesWon(foundUser.getGamesWon() + 1);
        }
        foundUser.setDotsEaten(foundUser.getDotsEaten() + dotsEaten);
        foundUser.setDeaths(foundUser.getDeaths() + deaths);

        repo.save(foundUser);
    }

    public UserStatsDTO getUserStats(String username) {
        User user = getUserByUsername(username);

        int gamesPlayed = user.getGamesPlayed();
        int gamesWon = user.getGamesWon();
        int gamesLost = Math.max(0, gamesPlayed - gamesWon);
        int kills = user.getDotsEaten();
        int deaths = user.getDeaths();

        double winPerc = gamesPlayed > 0 ? (gamesWon  * 100.0 / gamesPlayed) : 0.0;
        double lossPerc = gamesPlayed > 0 ? (gamesLost * 100.0 / gamesPlayed) : 0.0;
        double avgKills = gamesPlayed > 0 ? ((double) kills / gamesPlayed) : 0.0;
        double avgDeaths = gamesPlayed > 0 ? ((double) deaths    / gamesPlayed) : 0.0;

        return new UserStatsDTO(
            user.getUsername(),
            user.getEmail(),
            user.getCreatedAt(),
            gamesPlayed,
            gamesWon,
            gamesLost,
            deaths,
            kills,
            winPerc,
            lossPerc,
            avgKills,
            avgDeaths
        );
    }
}