package budgeteur.data

import arrow.core.Either
import arrow.core.raise.Raise
import budgeteur.shared.DomainError

/**
 * A failed check of a database constraint, with a message a user can act on.
 * Narrower than [DomainError] so combining failures cannot misclassify one.
 */
@JvmInline
value class ConstraintError(val message: String)

/**
 * Explicit checks for the database's integrity constraints. SQLite does not
 * always say which column broke a constraint, so handlers check first.
 */
object Constraints {
    /** Raises one [DomainError.ValidationFailed] that lists every failed check. */
    fun Raise<DomainError>.requireAll(vararg checks: Either<ConstraintError, Unit>) {
        val failures = checks.mapNotNull { it.leftOrNull()?.message }
        if (failures.isNotEmpty()) raise(DomainError.ValidationFailed(failures.joinToString("; ")))
    }
}
