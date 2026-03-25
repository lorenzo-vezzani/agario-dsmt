package it.unipi.dsmt.exception;

public class InvalidEmailException extends RuntimeException {
    public InvalidEmailException() {
        super("Invalid email address");
    }
}
