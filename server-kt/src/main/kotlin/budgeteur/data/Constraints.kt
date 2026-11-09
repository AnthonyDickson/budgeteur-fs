package budgeteur.data

import arrow.core.raise.Raise
import arrow.core.raise.context.either
import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.TAGS
import budgeteur.shared.DomainError
import java.util.UUID
import org.jooq.DSLContext

/**
 * A failed check of a database constraint, with a message a user can act on. Narrower than
 * [DomainError] so combining failures cannot misclassify one.
 */
@JvmInline value class ConstraintError(val message: String)

/**
 * Runs every check of the database's integrity constraints, then raises one
 * [DomainError.ValidationFailed] that lists each failure. SQLite does not always say which column
 * broke a constraint, so handlers check first.
 */
context(_: Raise<DomainError>)
fun requireAll(vararg checks: context(Raise<ConstraintError>) () -> Unit) {
    val failures = checks.mapNotNull { check -> either { check() }.leftOrNull() }
    ensure(failures.isEmpty()) {
        DomainError.ValidationFailed(failures.joinToString("; ") { it.message })
    }
}

/** The tag, when one is referenced, exists and belongs to the user. */
context(_: Raise<ConstraintError>)
fun DSLContext.requireTagIfReferenced(userId: String, tagId: UUID?) {
    if (tagId == null) return
    ensure(fetchExists(TAGS, TAGS.ID.eq(tagId), TAGS.USER_ID.eq(userId))) {
        ConstraintError("Could not find a tag with the ID $tagId")
    }
}

/** The account, when one is referenced, exists and belongs to the user. */
context(_: Raise<ConstraintError>)
fun DSLContext.requireAccountIfReferenced(userId: String, accountId: UUID?) {
    if (accountId == null) return
    ensure(fetchExists(ACCOUNTS, ACCOUNTS.ID.eq(accountId), ACCOUNTS.USER_ID.eq(userId))) {
        ConstraintError("Could not find an account with the ID $accountId")
    }
}
