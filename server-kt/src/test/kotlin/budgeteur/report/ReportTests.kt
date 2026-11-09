package budgeteur.report

import budgeteur.domain.Account
import budgeteur.domain.AccountName
import budgeteur.domain.BalanceObservation
import budgeteur.domain.BalanceSheetHistory
import budgeteur.domain.BalanceSheetItem
import budgeteur.domain.Entry
import budgeteur.domain.Frequency
import budgeteur.domain.ItemName
import budgeteur.domain.ItemObservation
import budgeteur.domain.Magnitude
import budgeteur.domain.Money
import budgeteur.domain.ReportingPeriod
import budgeteur.domain.Side
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName
import budgeteur.domain.Term
import budgeteur.feature.report.Change
import budgeteur.feature.report.compute
import budgeteur.feature.report.period
import budgeteur.feature.report.range
import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReportTests {
    private fun date(month: Int, day: Int) = LocalDate.of(2026, month, day)

    private fun dollars(amount: Long) = Money(amount * 100)

    private val house =
        BalanceSheetItem(UUID.randomUUID(), ItemName.unsafe("House"), Side.Asset, Term.NonCurrent)
    private val everyday =
        Account(UUID.randomUUID(), null, AccountName.unsafe("Everyday"), Term.Current)

    /** A house revalued from 400k to 410k in March, and an account that gains March's 3k. */
    private val history =
        BalanceSheetHistory(
            listOf(
                house to
                    listOf(
                        ItemObservation(date(1, 10), Magnitude.unsafe(dollars(400000))),
                        ItemObservation(date(3, 20), Magnitude.unsafe(dollars(410000))),
                    )
            ),
            listOf(
                everyday to
                    listOf(
                        BalanceObservation(date(2, 25), dollars(5000)),
                        BalanceObservation(date(3, 31), dollars(8000)),
                    )
            ),
        )

    private val salary =
        Tag(UUID.randomUUID(), TagName.unsafe("Salary"), TagColor.Green, TagKind.Income)

    private val entries =
        listOf(Entry(date(3, 1), dollars(5000), salary), Entry(date(3, 2), dollars(-2000), null))

    private fun month(m: Int) = ReportingPeriod.containing(Frequency.Monthly, date(m, 1))

    /** The monthly reports on [today] for data from 10 January. */
    private fun rangeOn(today: LocalDate) = range(Frequency.Monthly, today, date(1, 10))

    @Test
    fun `a report splits the change in net worth`() {
        val report =
            compute(date(10, 14), rangeOn(date(10, 14)), month(3), history, entries, listOf())

        assertEquals(dollars(405000), report.opening.netWorth, "at the end of February")
        assertEquals(dollars(418000), report.closing.netWorth, "at the end of March")
        assertEquals(
            Change(dollars(13000), dollars(10000), dollars(3000)),
            report.change,
            "3k saved, 10k revalued, and 3k more current",
        )
        assertEquals(BigDecimal("60.00"), report.incomeStatement.savingsRate)
        assertTrue(report.complete)
        assertEquals(date(3, 31), report.closingDate)
    }

    @Test
    fun `the first report's change is not meaningful`() {
        val report =
            compute(date(10, 14), rangeOn(date(10, 14)), month(1), history, listOf(), listOf())

        assertNull(report.change, "January opens on an empty sheet")
        assertFalse(report.hasPrevious)
        assertTrue(report.hasNext)
    }

    @Test
    fun `a report to date closes on today`() {
        val report =
            compute(date(3, 15), rangeOn(date(3, 15)), month(3), history, entries, listOf())

        assertFalse(report.complete)
        assertEquals(date(3, 15), report.closingDate)
        assertEquals(dollars(405000), report.closing.netWorth, "later observations are not in")
        assertFalse(report.hasNext)
    }

    @Test
    fun `closed accounts with later transactions are named`() {
        val oldCard =
            everyday.copy(
                id = UUID.randomUUID(),
                name = AccountName.unsafe("Old card"),
                closedOn = date(3, 10),
            )
        val withCard = history.copy(accounts = history.accounts + (oldCard to listOf()))
        // The card was used in March and May after closing on 10 March.
        val afterClose = listOf(oldCard.id to date(3, 15), oldCard.id to date(5, 1))

        fun named(m: Int) =
            compute(date(10, 14), rangeOn(date(10, 14)), month(m), withCard, listOf(), afterClose)
                .closedAccountsWithTransactions
                .map { it.id }

        assertEquals(listOf(oldCard.id), named(3))
        assertEquals(listOf(), named(4))
        assertEquals(listOf(oldCard.id), named(5))
    }

    @Test
    fun `the default period is the latest complete one`() {
        fun pick(firstDate: LocalDate?, requested: LocalDate?) =
            period(range(Frequency.Monthly, date(3, 15), firstDate), requested)?.from

        assertEquals(date(2, 1), pick(date(1, 10), null), "February, since March is to date")
        assertEquals(date(3, 1), pick(date(3, 2), null), "March when the data starts in March")
        assertEquals(date(3, 1), pick(null, null), "no data yet")
        assertEquals(date(1, 1), pick(date(1, 10), date(1, 31)), "the period containing the date")
        assertNull(pick(date(1, 10), date(4, 1)), "no report after today's period")
        assertNull(pick(date(1, 10), LocalDate.of(2025, 12, 31)), "none before the first data")
    }
}
