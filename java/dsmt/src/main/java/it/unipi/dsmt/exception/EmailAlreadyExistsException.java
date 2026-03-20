package it.unipi.dsmt.exception;

public class EmailAlreadyExistsException extends RuntimeException {

    public EmailAlreadyExistsException() {
        super("email already exists");
    }
}
