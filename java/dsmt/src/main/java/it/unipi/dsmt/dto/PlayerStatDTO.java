package it.unipi.dsmt.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public class PlayerStatDTO {
    @JsonProperty("id")
    public String id;

    @JsonProperty("k")
    public int kills;

    @JsonProperty("d")
    public int deaths;
}
