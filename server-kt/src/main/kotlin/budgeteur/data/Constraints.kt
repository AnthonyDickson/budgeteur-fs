package budgeteur.data

import arrow.core.raise.Raise
import arrow.core.raise.context.either
import arrow.core.raise.context.ensure
import budgeteur.shared.DomainError

/**
 * A failed check of a database constraint, with a message a user can act on.
 * Narrower than [DomainError] so combining failures cannot misclassify one.
 */
@JvmInline
value class ConstraintError(val message: String)

/**
 * Runs every check of the database's integrity constraints, then raises one
 * [DomainError.ValidationFailed] that lists each failure. SQLite does not
 * always say which column broke a constraint, so handlers check first.
 */
context(_: Raise<DomainError>)
fun requireAll(vararg checks: context(Raise<ConstraintError>) () -> Unit) {
    val failures = checks.mapNotNull { check -> either { check() }.leftOrNull() }
    ensure(failures.isEmpty()) { DomainError.ValidationFailed(failures.joinToString("; ") { it.message }) }
}
