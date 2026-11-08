package budgeteur.shared

/** Every way a handler can fail. Handlers return these; no exception escapes them. */
sealed interface DomainError {
    /** The client sent input that breaks a domain rule, including database constraints. */
    data class ValidationFailed(val message: String) : DomainError

    data class NotFound(val message: String) : DomainError

    /** The request carried no `sub` claim. */
    data object Unauthorised : DomainError

    /**
     * A database constraint the handler did not check first. Handlers check
     * constraints through [budgeteur.data.Constraints] so this marks a gap.
     */
    data class Conflict(val cause: Throwable) : DomainError

    data class DatabaseError(val cause: Throwable) : DomainError

    data class UnhandledException(val cause: Throwable) : DomainError
}
