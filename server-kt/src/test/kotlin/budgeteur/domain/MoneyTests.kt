package budgeteur.domain

import arrow.core.raise.context.either
import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class MoneyTests {
    private fun parse(raw: String) = either { Money.parse(raw) }

    @Test
    fun `an amount parses to cents`() {
        assertEquals(Money(1234), parse("12.34").getOrNull())
        assertEquals(Money(-500), parse("-5").getOrNull())
        assertEquals(Money(5), parse("0.05").getOrNull())
    }

    @Test
    fun `fractions of a cent round to the nearest cent, midpoint away from zero`() {
        assertEquals(Money(1235), parse("12.345").getOrNull())
        assertEquals(Money(-1235), parse("-12.345").getOrNull())
        assertEquals(Money(1234), parse("12.3449").getOrNull())
    }

    @Test
    fun `only plain decimals parse`() {
        listOf("", "abc", "1e3", "+1", "1,000", " 1", "1.", ".5", "$1", "1.2.3").forEach {
            assertTrue(parse(it).isLeft(), "\"$it\" should not parse")
        }
    }

    @Test
    fun `an amount beyond a Long of cents is rejected`() {
        assertEquals(Money(Long.MAX_VALUE), parse("92233720368547758.07").getOrNull())
        assertTrue(parse("92233720368547758.08").isLeft())
        assertEquals(Money(Long.MIN_VALUE), parse("-92233720368547758.08").getOrNull())
        assertTrue(parse("-92233720368547758.09").isLeft())
    }

    @Test
    fun `an amount is written with two decimal places`() {
        assertEquals("12.30", Money(1230).toString())
        assertEquals("-0.05", Money(-5).toString())
        assertEquals("0.00", Money.ZERO.toString())
    }

    @Test
    fun `computed amounts round as parsed ones do`() {
        assertEquals(Money(-1235), Money.round(BigDecimal("-12.345")))
    }

    @Test
    fun `arithmetic throws rather than overflowing`() {
        assertFailsWith<ArithmeticException> { Money(Long.MAX_VALUE) + Money(1) }
        assertFailsWith<ArithmeticException> { -Money(Long.MIN_VALUE) }
    }

    @Test
    fun `amounts sum exactly`() {
        assertEquals(Money(30), listOf(Money(10), Money(20)).sum())
        assertEquals(Money.ZERO, emptyList<Money>().sum())
    }
}
