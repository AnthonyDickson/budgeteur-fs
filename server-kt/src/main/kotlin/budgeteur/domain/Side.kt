package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull

/**
 * Which side of the balance sheet a line is on: something owned (an asset) or owed (a liability).
 * Fixed for an item; for an account it follows the sign of the balance. See decisions 3 and 5 in
 * docs/balance-sheet.md.
 */
enum class Side {
    Asset,
    Liability;

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): Side =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for Side, expecting one of \"Asset\" or " +
                    "\"Liability\"."
            }
    }
}
