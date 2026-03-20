package it.unipi.dsmt.dto;

import jakarta.validation.constraints.NotBlank;

public class LoginResponseDTO {

    @NotBlank
    private String message;

    private String token;

    public LoginResponseDTO(@NotBlank String message, String token) {
        this.message = message;
        this.token = token;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(@NotBlank String message) {
        this.message = message;
    }

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }
}
