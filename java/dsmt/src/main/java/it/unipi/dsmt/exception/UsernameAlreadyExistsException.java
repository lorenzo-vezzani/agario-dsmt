package it.unipi.dsmt.exception;

public class UsernameAlreadyExistsException extends RuntimeException {
    public UsernameAlreadyExistsException() {
        super("username already exists");
    }
}
