package budgeteur.shared

/**
 * The failures a handler expects and raises. Anything unexpected, such as a database error, is an
 * exception that the StatusPages plugin turns into a 500.
 */
sealed interface DomainError {
    /** The client sent input that breaks a domain rule, including database constraints. */
    data class ValidationFailed(val message: String) : DomainError

    data class NotFound(val message: String) : DomainError
}
