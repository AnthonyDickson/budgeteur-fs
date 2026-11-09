package budgeteur.domain

import arrow.core.raise.context.either
import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AccountTests {
    private fun canonical(raw: String) = either { AccountNumber.create(raw) }.map { it.value }

    @Test
    fun `bank account numbers have one canonical form`() {
        listOf(
                "12-3456-0789012-00",
                "12-3456-0789012-000",
                "12-3456-789012-00",
                "12 3456 0789012 00",
                "  12-3456-0789012-00  ",
                "123456078901200",
                "1234560789012000",
            )
            .forEach { assertEquals("12-3456-0789012-000", canonical(it).getOrNull(), "\"$it\"") }
    }

    @Test
    fun `the suffix keeps its value when padded`() {
        assertEquals("12-3456-0789012-001", canonical("12-3456-0789012-01").getOrNull())
        assertNotEquals(canonical("12-3456-0789012-01"), canonical("12-3456-0789012-00"))
    }

    @Test
    fun `masked card numbers are kept as printed`() {
        assertEquals("XXXX-XXXX-XXXX-1234", canonical("XXXX-XXXX-XXXX-1234").getOrNull())
        assertEquals("4835-****-****-1234", canonical("4835-****-****-1234").getOrNull())
    }

    @Test
    fun `anything else is rejected`() {
        listOf(
                "",
                "12-3456-07890123-00",
                "12-3456-0789012-0000",
                "1-3456-0789012-00",
                "12345607890",
                "1234-5678-9012-3456",
                "XXXX-XXXX-XXXX-XXXX",
                "Savings",
                "١٢-٣٤٥٦-٠٧٨٩٠١٢-٠٠",
            )
            .forEach { assertTrue(canonical(it).isLeft(), "\"$it\" should be rejected") }
    }

    @Test
    fun `a name is trimmed and cannot be blank`() {
        assertEquals("Savings", either { AccountName.create("  Savings ") }.getOrNull()?.value)
        assertTrue(either { AccountName.create(" ") }.isLeft())
        assertTrue(either { AccountName.create("a".repeat(AccountName.MAX_LENGTH + 1)) }.isLeft())
    }

    @Test
    fun `the latest accepted date is the server's UTC date plus one day`() {
        // 11:30 on 8 March in New Zealand is still 7 March in UTC.
        val now = Instant.parse("2026-03-07T22:30:00Z")
        assertEquals(LocalDate.of(2026, 3, 8), latestAcceptedDate(now))

        assertTrue(either { requireAsOfDate(now, LocalDate.of(2026, 3, 8)) }.isRight())
        assertTrue(either { requireAsOfDate(now, LocalDate.of(2026, 3, 9)) }.isLeft())
        assertTrue(either { requireCloseDate(now, LocalDate.of(2026, 3, 9)) }.isLeft())
    }

    @Test
    fun `transactions after close summarise their count and latest date`() {
        val dates = listOf("2026-03-09", "2026-03-11", "2026-03-10").map(LocalDate::parse)
        assertEquals(
            TransactionsAfterClose(3, LocalDate.of(2026, 3, 11)),
            TransactionsAfterClose.of(dates),
        )
        assertEquals(null, TransactionsAfterClose.of(emptyList()))
    }
}
