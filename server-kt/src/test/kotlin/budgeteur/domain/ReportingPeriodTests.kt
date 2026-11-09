package budgeteur.domain

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class ReportingPeriodTests {
    private fun days(frequency: Frequency, date: String) =
        ReportingPeriod.containing(frequency, LocalDate.parse(date)).let {
            it.from.toString() to it.to.toString()
        }

    @Test
    fun `a month runs from its first day to its last`() {
        assertEquals("2028-02-01" to "2028-02-29", days(Frequency.Monthly, "2028-02-15"))
    }

    @Test
    fun `quarters are calendar quarters`() {
        assertEquals("2026-04-01" to "2026-06-30", days(Frequency.Quarterly, "2026-06-30"))
        assertEquals("2026-10-01" to "2026-12-31", days(Frequency.Quarterly, "2026-10-01"))
    }

    @Test
    fun `a financial year runs from 1 April to 31 March`() {
        assertEquals("2025-04-01" to "2026-03-31", days(Frequency.FinancialYear, "2026-03-31"))
        assertEquals("2026-04-01" to "2027-03-31", days(Frequency.FinancialYear, "2026-04-01"))
    }

    @Test
    fun `periods step back and forward across year boundaries`() {
        val january = ReportingPeriod.containing(Frequency.Monthly, LocalDate.of(2026, 1, 15))
        assertEquals(LocalDate.of(2025, 12, 1), january.previous().from)
        assertEquals(january, january.previous().next())

        val q1 = ReportingPeriod.containing(Frequency.Quarterly, LocalDate.of(2026, 2, 1))
        assertEquals(LocalDate.of(2025, 10, 1), q1.previous().from)
    }

    @Test
    fun `each frequency has its label`() {
        val date = LocalDate.of(2026, 3, 10)
        assertEquals(
            listOf("March 2026", "Q1 2026", "2026", "2025/26"),
            Frequency.entries.map { ReportingPeriod.containing(it, date).label },
        )
        assertEquals(
            "2099/00",
            ReportingPeriod.containing(Frequency.FinancialYear, LocalDate.of(2099, 4, 1)).label,
            "the century wraps",
        )
    }

    @Test
    fun `a period is complete from its last day`() {
        val march = ReportingPeriod.containing(Frequency.Monthly, LocalDate.of(2026, 3, 10))
        assertEquals(
            listOf(false, true, true),
            listOf(30, 31).map { march.isComplete(LocalDate.of(2026, 3, it)) } +
                march.isComplete(LocalDate.of(2026, 4, 1)),
        )
    }
}
