package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import java.time.LocalDate
import java.util.UUID

/** An item's name, e.g. "House" or "Mortgage": trimmed, non-blank, at most [MAX_LENGTH]. */
@JvmInline
value class ItemName private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 128

        context(_: Raise<String>)
        fun create(raw: String): ItemName {
            val name = raw.trim()
            ensure(name.isNotEmpty()) { "Item name cannot be null or just whitespace" }
            ensure(name.length <= MAX_LENGTH) {
                "Item name is too long. Names must be at most $MAX_LENGTH characters, but got " +
                    "${name.length}"
            }
            return ItemName(name)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = ItemName(value)
    }
}

/**
 * An item's value as a positive magnitude. Its direction is the owning item's [Side], so the two
 * cannot disagree. An account's balance is signed instead; see [BalanceObservation].
 */
@JvmInline
value class Magnitude private constructor(val amount: Money) {
    companion object {
        context(_: Raise<String>)
        fun create(amount: Money): Magnitude {
            ensure(amount >= Money.ZERO) {
                "Value must be a positive magnitude. Use Side to record whether the amount is an " +
                    "asset or a liability."
            }
            return Magnitude(amount)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(amount: Money) = Magnitude(amount)
    }
}

/** A single balance sheet line that is not an account: one asset or one liability. */
data class BalanceSheetItem(
    val id: UUID,
    val name: ItemName,
    /** Fixed at creation. */
    val side: Side,
    val term: Term,
    /**
     * The date the item was sold or repaid; null while it is held. See decision 4 in
     * docs/reports.md.
     */
    val closedOn: LocalDate? = null,
)

/**
 * A value an item had as of a date, entered by hand. An item has at most one per date: a new one
 * replaces any on its date. See decision 2 in docs/reports.md.
 */
data class ItemObservation(val asOf: LocalDate, val value: Magnitude)

/**
 * An item and its current value: the observation with the latest as-of date. Every item has one, as
 * it is created with its first.
 */
data class ItemValue(val item: BalanceSheetItem, val current: ItemObservation)
