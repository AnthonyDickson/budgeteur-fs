package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull

/**
 * Whether a balance sheet line is expected to be realised (assets) or settled (liabilities) within
 * about 12 months. Items and accounts both have one. See decision 7 in docs/balance-sheet.md.
 */
enum class Term {
    Current,
    NonCurrent;

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): Term =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for Term, expecting one of \"Current\" or " +
                    "\"NonCurrent\"."
            }
    }
}
