package budgeteur.dashboard

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
import budgeteur.feature.dashboard.Comparison
import budgeteur.feature.dashboard.HistoryMonth
import budgeteur.feature.dashboard.HistoryTotals
import budgeteur.feature.dashboard.compute
import budgeteur.feature.dashboard.month
import budgeteur.feature.dashboard.periods
import budgeteur.feature.dashboard.periodsFor
import budgeteur.feature.dashboard.readPeriod
import budgeteur.feature.dashboard.runway
import budgeteur.feature.dashboard.sameDays
import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun date(year: Int, month: Int, day: Int): LocalDate = LocalDate.of(year, month, day)

private fun dollars(amount: Long) = Money(amount * 100)

private fun tag(name: String, kind: TagKind) =
    Tag(UUID.randomUUID(), TagName.unsafe(name), TagColor.Green, kind)

class DashboardPeriodsTests {
    private fun sameDays(today: LocalDate, year: Int, month: Int) =
        sameDays(today, ReportingPeriod.containing(Frequency.Monthly, date(year, month, 1))).let {
            it.from to it.to
        }

    private fun List<ReportingPeriod>.starts() = map { it.from }

    private fun monthsFrom(year: Int, month: Int, count: Int) =
        (0 until count).map { date(year, month, 1).plusMonths(it.toLong()) }

    @Test
    fun `the baseline days run to today's day of the month`() {
        assertEquals(date(2026, 9, 1) to date(2026, 9, 14), sameDays(date(2026, 10, 14), 2026, 9))
        assertEquals(
            date(2026, 12, 1) to date(2026, 12, 15),
            sameDays(date(2027, 1, 15), 2026, 12),
            "across a year boundary",
        )
    }

    @Test
    fun `the baseline day is clamped to a shorter month`() {
        assertEquals(date(2026, 2, 1) to date(2026, 2, 28), sameDays(date(2026, 3, 30), 2026, 2))
        assertEquals(date(2028, 2, 1) to date(2028, 2, 29), sameDays(date(2028, 3, 30), 2028, 2))
    }

    @Test
    fun `on a month's last day the whole baseline month is used`() {
        assertEquals(date(2026, 8, 1) to date(2026, 8, 31), sameDays(date(2026, 9, 30), 2026, 8))
        assertEquals(date(2027, 1, 1) to date(2027, 1, 31), sameDays(date(2027, 2, 28), 2027, 1))
        assertEquals(
            date(2028, 1, 1) to date(2028, 1, 28),
            sameDays(date(2028, 2, 28), 2028, 1),
            "28 February of a leap year is not its last day",
        )
    }

    @Test
    fun `a user with years of data has twelve months and this one`() {
        val today = date(2026, 10, 14)
        val periods = periods(today, date(2020, 1, 1), date(2020, 1, 1))

        assertEquals(monthsFrom(2025, 10, 13), periods.historyMonths.starts())
        assertEquals(monthsFrom(2025, 10, 12), periods.baselineMonths.starts())
        assertEquals(date(2026, 10, 1) to today, periods.monthToDate.let { it.from to it.to })
        assertEquals(date(2025, 10, 1) to today, readPeriod(periods).let { it.from to it.to })
    }

    @Test
    fun `the history starts at the month of the first data`() {
        val periods = periods(date(2026, 10, 14), date(2026, 5, 20), date(2026, 6, 10))
        assertEquals(monthsFrom(2026, 5, 6), periods.historyMonths.starts())
        assertEquals(
            monthsFrom(2026, 7, 3),
            periods.baselineMonths.starts(),
            "June has partial data, so the baseline starts in July",
        )
    }

    @Test
    fun `a month starting on the first transaction is a baseline month`() {
        val periods = periods(date(2026, 10, 14), date(2026, 8, 1), date(2026, 8, 1))
        assertEquals(monthsFrom(2026, 8, 2), periods.baselineMonths.starts())
    }

    @Test
    fun `without transactions there are no baseline months`() {
        val periods = periods(date(2026, 10, 14), date(2026, 3, 1), null)
        assertEquals(8, periods.historyMonths.size, "March to October")
        assertTrue(periods.baselineMonths.isEmpty())
    }

    @Test
    fun `without data, or with only future data, the history is today's month`() {
        listOf(null, date(2026, 12, 1)).forEach { first ->
            val periods = periods(date(2026, 10, 14), first, first)
            assertEquals(listOf(date(2026, 10, 1)), periods.historyMonths.starts(), "$first")
        }
    }
}

class DashboardMonthTests {
    private val salary = tag("Salary", TagKind.Income)
    private val rent = tag("Rent", TagKind.Expense)
    private val groceries = tag("Groceries", TagKind.Expense)
    private val fuel = tag("Fuel", TagKind.Expense)

    private fun entry(month: Int, day: Int, amount: Long, tag: Tag?) =
        Entry(date(2026, month, day), dollars(amount), tag)

    /** The figures on 14 October for a user whose first transaction was on [first]. */
    private fun monthFrom(first: LocalDate, vararg entries: Entry) =
        month(periods(date(2026, 10, 14), first, first), entries.toList())

    /** The figures on 14 October with August and September as the baseline months. */
    private fun month(vararg entries: Entry) = monthFrom(date(2026, 8, 1), *entries)

    private fun comparison(baseline: Long, change: Long, percent: String?) =
        Comparison(dollars(baseline), dollars(change), percent?.let(::BigDecimal))

    @Test
    fun `a baseline is the mean over the same days of each month`() {
        val figures =
            month(
                entry(8, 5, -100, groceries),
                entry(8, 20, -500, groceries),
                entry(9, 14, -300, groceries),
                entry(10, 3, -250, groceries),
            )

        assertEquals(
            comparison(200, 50, "25.00"),
            figures.expenses.comparison,
            "the 20th is after the 14th, so the mean is of 100 and 300",
        )
        assertEquals(figures.expenses.comparison, figures.expenseLines.single().comparison)
        assertEquals(2, figures.baselineMonthCount)
    }

    @Test
    fun `a baseline is rounded to cents`() {
        val figures = monthFrom(date(2026, 7, 1), entry(7, 1, -100, groceries))
        assertEquals(Money(3333), figures.expenses.comparison?.baseline, "100 over three months")
    }

    @Test
    fun `a usual expense with nothing this month is a zero line`() {
        val figures =
            month(
                entry(8, 1, -2000, rent),
                entry(9, 1, -2000, rent),
                entry(10, 3, -250, groceries),
                entry(10, 4, -20, null),
            )

        assertEquals(listOf(groceries, rent, null), figures.expenseLines.map { it.tag })
        val line = figures.expenseLines.first { it.tag == rent }
        assertEquals(Money.ZERO, line.amount)
        assertEquals(BigDecimal("0.00"), line.share)
        assertEquals(comparison(2000, -2000, "-100.00"), line.comparison)
    }

    @Test
    fun `a zero or negative baseline has no change percentage`() {
        assertEquals(
            comparison(0, 80, null),
            month(entry(8, 1, -2000, rent), entry(10, 3, -80, fuel))
                .expenseLines
                .first { it.tag == fuel }
                .comparison,
        )
        assertEquals(
            comparison(-1000, 2000, null),
            month(entry(8, 1, 1000, salary), entry(8, 2, -3000, rent), entry(10, 1, 1000, salary))
                .netIncome
                .comparison,
        )
    }

    @Test
    fun `the savings rate baseline is the rate of the baseline means`() {
        val figures =
            month(
                entry(8, 1, 1000, salary),
                entry(8, 2, -900, rent),
                entry(9, 1, 9000, salary),
                entry(9, 2, -900, rent),
                entry(10, 1, 5000, salary),
                entry(10, 2, -1500, rent),
            )
        assertEquals(BigDecimal("70.00"), figures.savingsRate)
        assertEquals(BigDecimal("82.00"), figures.savingsRateBaseline, "not the mean of 10 and 90")
        assertEquals(BigDecimal("-12.00"), figures.savingsRateChange)
    }

    @Test
    fun `with no baseline months nothing is compared`() {
        val figures =
            monthFrom(
                date(2026, 9, 10),
                entry(9, 10, 3000, salary),
                entry(10, 1, 5000, salary),
                entry(10, 3, -250, groceries),
            )
        assertEquals(0, figures.baselineMonthCount)
        assertNull(figures.income.comparison)
        assertNull(figures.savingsRateBaseline)
        assertEquals(listOf(null), figures.incomeLines.map { it.comparison })
    }

    @Test
    fun `the latest transaction is the month's last date`() {
        val figures =
            month(entry(9, 30, -10, fuel), entry(10, 9, -10, fuel), entry(10, 3, -10, fuel))
        assertEquals(date(2026, 10, 9), figures.latestTransaction)
        assertNull(month(entry(9, 30, -10, fuel)).latestTransaction)
    }
}

class DashboardHistoryTests {
    private val today = date(2026, 10, 14)
    private val everyday =
        Account(UUID.randomUUID(), null, AccountName.unsafe("Everyday"), Term.Current)
    private val car =
        BalanceSheetItem(UUID.randomUUID(), ItemName.unsafe("Car"), Side.Asset, Term.NonCurrent)

    private fun balance(month: Int, day: Int, amount: Long) =
        BalanceObservation(date(2026, month, day), dollars(amount))

    private fun value(month: Int, day: Int, amount: Long) =
        ItemObservation(date(2026, month, day), Magnitude.unsafe(dollars(amount)))

    /** A car valued from July, and an everyday account with its first balance in August. */
    private val balanceHistory =
        BalanceSheetHistory(
            listOf(car to listOf(value(7, 10, 10000), value(9, 15, 9000))),
            listOf(everyday to listOf(balance(8, 20, 4000), balance(10, 5, 6000))),
        )

    private val salary = tag("Salary", TagKind.Income)

    private fun entry(month: Int, day: Int, amount: Long, tag: Tag?) =
        Entry(date(2026, month, day), dollars(amount), tag)

    /** Salary and spending from 1 August: two baseline months and the month to date. */
    private val entries =
        listOf(
            entry(8, 1, 5000, salary),
            entry(8, 9, -3000, null),
            entry(9, 1, 5000, salary),
            entry(9, 9, -1000, null),
            entry(10, 1, 5000, salary),
            entry(10, 9, -500, null),
            entry(10, 20, -100, null),
        )

    private fun compute(
        history: BalanceSheetHistory,
        firstTransaction: LocalDate?,
        entries: List<Entry>,
    ) = compute(periodsFor(today, history, firstTransaction), history, entries)

    private val figures = compute(balanceHistory, date(2026, 8, 1), entries)

    private fun List<HistoryMonth>.of(month: Int) = first { it.month.from.monthValue == month }

    @Test
    fun `the history starts at the first observation`() {
        assertEquals(
            listOf(7, 8, 9, 10).map { date(2026, it, 1) },
            figures.history.map { it.month.from },
        )
    }

    @Test
    fun `each month has its statement and closing position`() {
        val september = figures.history.of(9)
        assertEquals(
            listOf(dollars(5000), dollars(1000), dollars(4000)),
            listOf(september.income, september.expenses, september.netIncome),
        )
        assertEquals(dollars(13000), september.netWorth, "the car's and the account's")
        assertEquals(dollars(4000), september.workingCapital, "the account only")
    }

    @Test
    fun `the month to date runs to today`() {
        val october = figures.history.of(10)
        assertEquals(today, october.closingDate)
        assertFalse(october.complete)
        assertEquals(dollars(500), october.expenses, "the 20th is after today")
        assertEquals(dollars(15000), october.netWorth)
    }

    @Test
    fun `a month before any observation has no position`() {
        val history =
            compute(
                BalanceSheetHistory(emptyList(), listOf(everyday to listOf(balance(9, 1, 1)))),
                date(2026, 8, 1),
                entries,
            )
        assertNull(history.history.of(8).netWorth)
        assertNull(history.history.of(8).workingCapital)
    }

    @Test
    fun `totals cover the baseline months only`() {
        assertEquals(
            HistoryTotals(
                monthCount = 2,
                income = dollars(10000),
                expenses = dollars(4000),
                netIncome = dollars(6000),
                savingsRate = BigDecimal("60.00"),
                averageIncome = dollars(5000),
                averageExpenses = dollars(2000),
                averageNetIncome = dollars(3000),
            ),
            figures.totals,
        )
        val none = compute(balanceHistory, null, emptyList())
        assertNull(none.totals)
        assertNull(none.position.runway)
    }

    @Test
    fun `runway is working capital in months of expenses`() {
        assertEquals(BigDecimal("3.0"), figures.position.runway)
        assertEquals(BigDecimal("0.0"), runway(dollars(-500), figures.totals), "none")
        assertEquals(BigDecimal("0.5"), runway(dollars(1000), figures.totals))
        assertNull(runway(dollars(1000), figures.totals?.copy(averageExpenses = Money.ZERO)))
    }

    @Test
    fun `the position shows the oldest as-of date`() {
        assertEquals(date(2026, 9, 15), figures.position.oldestAsOf)
        assertFalse(figures.position.isEmpty)

        val empty = compute(BalanceSheetHistory(emptyList(), emptyList()), null, emptyList())
        assertTrue(empty.position.isEmpty)
        assertNull(empty.position.oldestAsOf)
        assertEquals(listOf(date(2026, 10, 1)), empty.history.map { it.month.from })
    }
}
