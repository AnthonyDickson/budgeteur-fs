package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.raise
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * The number a statement identifies an account by: an NZ bank account number in canonical form, or
 * a masked card number as the statement prints it. See decision 4 in docs/csv-import.md.
 */
@JvmInline
value class AccountNumber private constructor(val value: String) {
    companion object {
        // [0-9] rather than \d, which in some regex modes matches non-ASCII digits.

        /** Bank (2 digits), branch (4), account (up to 7), and suffix (2 or 3), separated. */
        private val separated = Regex("^([0-9]{2})[- ]([0-9]{4})[- ]([0-9]{1,7})[- ]([0-9]{2,3})$")

        /**
         * The same parts unseparated, which needs the account at seven digits to be unambiguous.
         */
        private val unseparated = Regex("^([0-9]{2})([0-9]{4})([0-9]{7})([0-9]{2,3})$")

        /** Three or four groups of digits, some masked with X or *, e.g. XXXX-XXXX-XXXX-1234. */
        private val maskedCard =
            Regex("^(?=.*[Xx*])(?=.*[0-9])[0-9Xx*]{4,6}(?:[- ][0-9Xx*]{4,6}){2,3}$")

        private val widths = listOf(2, 4, 7, 3)

        /** The account padded to seven digits and the suffix to three, joined by hyphens. */
        private fun canonical(parts: MatchResult) =
            parts.groupValues
                .drop(1)
                .zip(widths) { part, width -> part.padStart(width, '0') }
                .joinToString("-")

        /**
         * Parses an NZ bank account number into its canonical form, or accepts a masked card number
         * as printed. Surrounding whitespace is ignored.
         */
        context(_: Raise<String>)
        fun create(raw: String): AccountNumber {
            val number = raw.trim()
            val bank = separated.matchEntire(number) ?: unseparated.matchEntire(number)
            return when {
                bank != null -> AccountNumber(canonical(bank))
                maskedCard.matches(number) -> AccountNumber(number)
                else ->
                    raise(
                        "\"$number\" is not an account number. Expected an NZ bank account " +
                            "number such as 12-3456-0789012-00, or a masked card number such as " +
                            "XXXX-XXXX-XXXX-1234."
                    )
            }
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = AccountNumber(value)
    }
}

/** The user's alias for an account: trimmed, non-blank, at most [MAX_LENGTH]. Not unique. */
@JvmInline
value class AccountName private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 128

        context(_: Raise<String>)
        fun create(raw: String): AccountName {
            val name = raw.trim()
            ensure(name.isNotEmpty()) { "Account name cannot be null or just whitespace" }
            ensure(name.length <= MAX_LENGTH) {
                "Account name is too long. Names must be at most $MAX_LENGTH characters, but got " +
                    "${name.length}"
            }
            return AccountName(name)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = AccountName(value)
    }
}

/**
 * Somewhere the user's transactions happen: chequing, savings, a credit card. A source of balance
 * sheet lines alongside items. See decision 1 in docs/csv-import.md.
 */
data class Account(
    val id: UUID,
    /** Null for an account without one, which imports never match. */
    val number: AccountNumber?,
    val name: AccountName,
    /**
     * Which balance sheet group the account's line goes in. Its side follows its balance's sign.
     */
    val term: Term,
    /** Null while the account is open. See decision 4 in docs/reports.md. */
    val closedOn: LocalDate? = null,
)

/**
 * A balance an account had as of a date, from a statement or entered by hand. An account has at
 * most one per date: a new one replaces any on its date, whatever its source. See decision 3 in
 * docs/csv-import.md.
 */
data class BalanceObservation(
    val asOf: LocalDate,
    /** Signed: positive is an asset (owned), negative a liability (owed). */
    val balance: Money,
) {
    companion object {
        /** A balance the user enters by hand at the instant [now], which bounds its date. */
        context(_: Raise<String>)
        fun create(now: Instant, asOf: LocalDate, balance: Money) =
            BalanceObservation(requireAsOfDate(now, asOf), balance)
    }
}

/** An account and its current balance. See decision 3 in docs/csv-import.md. */
data class AccountBalance(
    val account: Account,
    /**
     * The observation with the latest as-of date, so an old statement never replaces a newer
     * balance. Null when the account has none: its balance is unknown.
     */
    val current: BalanceObservation?,
)

/**
 * A closed account's transactions dated after its close date. A closed account should have none, so
 * they suggest the close date is wrong. See decision 4 in docs/reports.md.
 */
data class TransactionsAfterClose(val count: Int, val latest: LocalDate) {
    companion object {
        /** The summary of an account's transaction dates after its close date, or null. */
        fun of(dates: List<LocalDate>): TransactionsAfterClose? =
            dates.maxOrNull()?.let { TransactionsAfterClose(dates.size, it) }
    }
}
