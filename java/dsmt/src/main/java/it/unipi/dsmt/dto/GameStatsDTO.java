package it.unipi.dsmt.dto;

import java.util.List;

public class GameStatsDTO {
    public String type;
    public List<BallsStateDTO> ordered_balls;
    public List<PlayerStatDTO> stats;
}
