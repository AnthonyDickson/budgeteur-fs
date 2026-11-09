package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import java.time.LocalDate
import java.util.UUID

/** A trimmed, non-blank description of at most [MAX_LENGTH] characters. */
@JvmInline
value class TransactionDescription private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 256

        context(_: Raise<String>)
        fun create(raw: String): TransactionDescription {
            val description = raw.trim()
            ensure(description.isNotEmpty()) { "Description cannot be null or just whitespace" }
            ensure(description.length <= MAX_LENGTH) {
                "Description is too long. Descriptions must be at most $MAX_LENGTH characters, " +
                    "but got ${description.length}"
            }
            return TransactionDescription(description)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = TransactionDescription(value)
    }
}

/**
 * The facts of what happened. Its tag is a [Categorisation], kept apart so tagging never changes
 * the facts.
 */
data class Transaction(
    val id: UUID,
    /** A debit is negative and a credit positive. */
    val amount: Money,
    val description: TransactionDescription,
    val date: LocalDate,
    /** Null when the account is unknown or does not apply, e.g. cash. */
    val accountId: UUID?,
)
