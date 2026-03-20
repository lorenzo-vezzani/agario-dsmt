package it.unipi.dsmt.exception;

import it.unipi.dsmt.dto.LoginResponseDTO;
import it.unipi.dsmt.dto.RegisterResponseDTO;
import org.jetbrains.annotations.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

@ControllerAdvice
class GlobalExceptionHandler {
    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    // ---------- HANDLERS FOR REGISTER ---------- //

    @ExceptionHandler(EmailAlreadyExistsException.class)
    public ResponseEntity<@NotNull RegisterResponseDTO> handleEmailAlreadyExistsException(EmailAlreadyExistsException ex) {
        return ResponseEntity
                .status(HttpStatus.CONFLICT)
                .body(new RegisterResponseDTO(ex.getMessage(), null));
    }

    @ExceptionHandler(UsernameAlreadyExistsException.class)
    public ResponseEntity<@NotNull RegisterResponseDTO> handleUsernameAlreadyExistsException(Exception ex) {
        return ResponseEntity
                .status(HttpStatus.CONFLICT)
                .body(new RegisterResponseDTO(ex.getMessage(), null));
    }

    // ------------------------------------------- //


    // ---------- HANDLERS FOR LOGIN ---------- //

    @ExceptionHandler(UserNotFoundException.class)
    public ResponseEntity<@NotNull LoginResponseDTO> handleUserNotFoundException(Exception ex) {
        return ResponseEntity
                .status(HttpStatus.NOT_FOUND)
                .body(new LoginResponseDTO(ex.getMessage(), null));
    }

    @ExceptionHandler(IncorrectPasswordException.class)
    public ResponseEntity<@NotNull LoginResponseDTO> handleIncorrectPasswordException(Exception ex) {
        return ResponseEntity
                .status(HttpStatus.UNAUTHORIZED)
                .body(new LoginResponseDTO(ex.getMessage(), null));
    }

    // ---------------------------------------- //


    // ---------- HANDLERS FOR JSON VALIDATION ---------- //

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<?> handleValidationErrors(MethodArgumentNotValidException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .build();
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<?> handleJsonParseError(HttpMessageNotReadableException ex) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .build();
    }

    // -------------------------------------------------- //


    @ExceptionHandler(Exception.class)
    public ResponseEntity<?> handleGenericException(Exception ex) {
        logger.error(ex.toString());
        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .build();
    }
}
