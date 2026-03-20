package it.unipi.dsmt.dto;

import jakarta.validation.constraints.NotBlank;

public class RegisterResponseDTO {

    @NotBlank
    private String message;

    private String username;

    public RegisterResponseDTO(@NotBlank String message, String username) {
        this.message = message;
        this.username = username;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(@NotBlank String message) {
        this.message = message;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }
}
