package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import java.math.BigDecimal
import java.math.RoundingMode

/**
 * A signed amount in whole cents. Every `Long` is a valid amount, so fractions of a cent cannot be
 * represented, and equality, ordering and sums are exact. Arithmetic throws on overflow rather than
 * wrapping, at about ±92 quadrillion dollars.
 *
 * Amounts are written as decimal strings with two places, e.g. `"-12.34"`, in JSON and in import
 * hashes alike.
 */
@JvmInline
value class Money(val cents: Long) : Comparable<Money> {
    operator fun plus(other: Money) = Money(Math.addExact(cents, other.cents))

    operator fun minus(other: Money) = Money(Math.subtractExact(cents, other.cents))

    operator fun unaryMinus() = Money(Math.negateExact(cents))

    fun abs() = Money(Math.absExact(cents))

    override fun compareTo(other: Money) = cents.compareTo(other.cents)

    /** For ratios, such as a tag's share of expenses. */
    fun toBigDecimal(): BigDecimal = BigDecimal.valueOf(cents, 2)

    /** Two decimal places, no exponent: `"0.05"`, `"-12.30"`. */
    override fun toString(): String = toBigDecimal().toPlainString()

    companion object {
        val ZERO = Money(0)

        private val decimal = Regex("""-?\d+(\.\d+)?""")

        /**
         * Rounds [amount] to cents, midpoint away from zero (`HALF_UP` in Java), as the F# server
         * does. Throws if the result is out of range, so it is for computed amounts; input goes
         * through [parse].
         */
        fun round(amount: BigDecimal) =
            Money(amount.setScale(2, RoundingMode.HALF_UP).unscaledValue().longValueExact())

        /**
         * Parses a plain decimal such as `"-12.345"`, rounding it to cents. Signs other than a
         * leading minus, exponents, separators and whitespace are rejected: the client sends none
         * of them, and an exponent would let a short string make `BigDecimal` build a huge number.
         */
        context(_: Raise<String>)
        fun parse(raw: String): Money {
            ensure(decimal.matches(raw)) {
                "\"$raw\" is not an amount, expecting a decimal such as \"-12.34\"."
            }
            val cents = BigDecimal(raw).setScale(2, RoundingMode.HALF_UP).unscaledValue()
            ensure(cents.bitLength() < Long.SIZE_BITS) { "\"$raw\" is too large for an amount." }
            return Money(cents.toLong())
        }
    }
}

fun Iterable<Money>.sum(): Money = fold(Money.ZERO, Money::plus)
