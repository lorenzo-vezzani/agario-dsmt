package it.unipi.dsmt.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

// DTO so that on user creation we can avoid to specify everything in the post request
public class RegisterRequestDTO {

    @NotBlank
    private String username;

    @NotBlank
    @Email(message = "Invalid email")
    private String email;

    @NotBlank
    private String password;

    // ---------- GETTERS AND SETTERS ---------- //
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}