package budgeteur.feature.dashboard

import budgeteur.domain.BalanceSheet
import budgeteur.domain.BalanceSheetHistory
import budgeteur.domain.Entry
import budgeteur.domain.Frequency
import budgeteur.domain.IncomeStatement
import budgeteur.domain.Money
import budgeteur.domain.Period
import budgeteur.domain.ReportingPeriod
import budgeteur.domain.StatementLine
import budgeteur.domain.Tag
import budgeteur.domain.dividedBy
import budgeteur.domain.percentOf
import budgeteur.domain.statementLineOrder
import budgeteur.domain.sum
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate

/** How many complete months the history covers at most. */
const val HISTORY_MONTH_COUNT = 12

/**
 * The periods the dashboard covers, all worked out from the client's today. See decisions 11, 12,
 * and 14 in docs/dashboard.md.
 */
data class DashboardPeriods(
    val today: LocalDate,
    /** The first of today's month up to today. */
    val monthToDate: Period,
    /**
     * Up to twelve complete months and today's month, oldest first, starting no earlier than the
     * month of the user's first data.
     */
    val historyMonths: List<ReportingPeriod>,
    /** The history's complete months that start on or after the user's first transaction. */
    val baselineMonths: List<ReportingPeriod>,
)

/** A figure's baseline and its change from it. See decision 12 in docs/dashboard.md. */
data class Comparison(
    /** The figure's mean over the same days of the baseline months. */
    val baseline: Money,
    val change: Money,
    /** The change as a percentage of the baseline, or null when the baseline is not positive. */
    val changePercent: BigDecimal?,
) {
    companion object {
        fun of(amount: Money, baseline: Money) =
            Comparison(baseline, amount - baseline, percentOf(baseline, amount - baseline))
    }
}

/** A total for the month to date, with its comparison once there are baseline months. */
data class Figure(val amount: Money, val comparison: Comparison?)

/**
 * One line of the month to date: a tag's net amount, or the untagged income or expenses. A tag with
 * nothing this month but an amount in the baseline is a line with a zero amount. [share] is an
 * expense line's percentage of the month's expenses.
 */
data class MonthLine(
    val tag: Tag?,
    val amount: Money,
    val share: BigDecimal?,
    val comparison: Comparison?,
)

/** The month to date against its baseline. */
data class MonthFigures(
    val period: Period,
    val income: Figure,
    val expenses: Figure,
    val netIncome: Figure,
    val savingsRate: BigDecimal?,
    /** The savings rate of the baseline income and net income. */
    val savingsRateBaseline: BigDecimal?,
    /** The savings rate minus its baseline, in percentage points. */
    val savingsRateChange: BigDecimal?,
    /** Largest first, with the untagged line last. */
    val incomeLines: List<MonthLine>,
    /** Largest first, with the untagged line last. */
    val expenseLines: List<MonthLine>,
    /** How many months the baselines are the mean of. Zero while the baseline is building. */
    val baselineMonthCount: Int,
    val latestTransaction: LocalDate?,
)

/** One month of the history: its income statement to its closing date, and the position then. */
data class HistoryMonth(
    val month: ReportingPeriod,
    /** The month's last day, or today for the month to date. */
    val closingDate: LocalDate,
    val complete: Boolean,
    val income: Money,
    val expenses: Money,
    val netIncome: Money,
    /** Null when no line on the closing date's balance sheet has a known balance. */
    val netWorth: Money?,
    val workingCapital: Money?,
)

/**
 * The baseline months' whole-month figures taken together. See decision 14 in docs/dashboard.md.
 */
data class HistoryTotals(
    val monthCount: Int,
    val income: Money,
    val expenses: Money,
    val netIncome: Money,
    /** Net income over income for the whole span. */
    val savingsRate: BigDecimal?,
    val averageIncome: Money,
    /** The figure runway divides by. */
    val averageExpenses: Money,
    val averageNetIncome: Money,
)

/** Where the user stands today. */
data class Position(
    /** Whether the balance sheet has no items or accounts. */
    val isEmpty: Boolean,
    val netWorth: Money,
    val workingCapital: Money,
    /** Working capital in months of average expenses. See decision 13 in docs/dashboard.md. */
    val runway: BigDecimal?,
    /** The earliest as-of date among the lines with a known balance. */
    val oldestAsOf: LocalDate?,
)

/** Every figure on the dashboard. */
data class DashboardFigures(
    val position: Position,
    val month: MonthFigures,
    /** Oldest first, ending with the month to date. */
    val history: List<HistoryMonth>,
    /** Null while there are no baseline months. */
    val totals: HistoryTotals?,
)

/** The closing date of a history month: its last day once it is complete, otherwise today. */
fun closingDate(today: LocalDate, month: ReportingPeriod): LocalDate =
    if (month.isComplete(today)) month.to else today

/** A month's first day to its closing date. */
fun monthPeriod(today: LocalDate, month: ReportingPeriod) =
    Period(month.from, closingDate(today, month))

/**
 * The days of a baseline month that match the month to date: from its first day to today's day of
 * the month. The day is clamped to the month's length, and on the last day of today's month the
 * whole baseline month is used: on 30 March the February days are 1 to 28, and on 30 September the
 * whole of August.
 */
fun sameDays(today: LocalDate, month: ReportingPeriod): Period {
    val current = ReportingPeriod.containing(Frequency.Monthly, today)
    val to =
        if (today == current.to) month.to
        else minOf(month.from.plusDays(today.dayOfMonth - 1L), month.to)
    return Period(month.from, to)
}

/**
 * The dashboard's periods for the client's today, given the user's first data date (observation or
 * transaction) and first transaction date.
 */
fun periods(
    today: LocalDate,
    firstData: LocalDate?,
    firstTransaction: LocalDate?,
): DashboardPeriods {
    val current = ReportingPeriod.containing(Frequency.Monthly, today)
    val earliest = current.from.minusMonths(HISTORY_MONTH_COUNT.toLong())
    // A user with no data has today's month only, as on the reports page.
    val first =
        if (firstData == null) current
        else ReportingPeriod.containing(Frequency.Monthly, maxOf(earliest, minOf(firstData, today)))
    val historyMonths =
        generateSequence(first) { it.next() }.takeWhile { it.from <= today }.toList()
    val baselineMonths =
        if (firstTransaction == null) emptyList()
        else historyMonths.filter { it.isComplete(today) && it.from >= firstTransaction }
    return DashboardPeriods(today, monthPeriod(today, current), historyMonths, baselineMonths)
}

/**
 * The dashboard's periods given the user's balance sheet history and first transaction date. The
 * history starts at the first observation or transaction, whichever is earlier.
 */
fun periodsFor(
    today: LocalDate,
    history: BalanceSheetHistory,
    firstTransaction: LocalDate?,
): DashboardPeriods =
    periods(
        today,
        listOfNotNull(firstTransaction, history.firstObservation).minOrNull(),
        firstTransaction,
    )

/** The one span the transactions are read for: the first history month's first day to today. */
fun readPeriod(periods: DashboardPeriods): Period =
    Period(periods.historyMonths.firstOrNull()?.from ?: periods.monthToDate.from, periods.today)

private fun List<Entry>.within(period: Period) = filter { it.date in period }

private fun statementFor(period: Period, entries: List<Entry>) =
    IncomeStatement.compute(period, entries.within(period))

/**
 * One side's lines: the month's, plus a zero line for each tag in the baseline with nothing this
 * month, each compared with its mean over the baseline statements.
 */
private fun lines(
    side: (IncomeStatement) -> List<StatementLine>,
    statement: IncomeStatement,
    baselines: List<IncomeStatement>,
    zeroShare: BigDecimal?,
): List<MonthLine> {
    val monthLines = side(statement)
    val baselineLines = baselines.flatMap(side)
    val monthTags = monthLines.map { it.tag }.toSet()
    val zeroLines =
        baselineLines
            .map { it.tag }
            .distinct()
            .filter { it !in monthTags }
            .map { StatementLine(it, Money.ZERO, zeroShare) }

    fun baselineOf(tag: Tag?): Money? =
        if (baselines.isEmpty()) null
        else
            baselineLines.filter { it.tag == tag }.map { it.amount }.sum().dividedBy(baselines.size)

    return (monthLines + zeroLines).sortedWith(statementLineOrder).map { line ->
        MonthLine(
            line.tag,
            line.amount,
            line.share,
            baselineOf(line.tag)?.let { Comparison.of(line.amount, it) },
        )
    }
}

/**
 * The month to date's income statement against its baseline: the mean of each total and line over
 * the same days of each baseline month. The savings rate's baseline is the rate of the baseline
 * means, not the mean of each month's rate, so a month with little income does not swing it. See
 * decisions 12 and 13 in docs/dashboard.md.
 */
fun month(periods: DashboardPeriods, entries: List<Entry>): MonthFigures {
    val statement = statementFor(periods.monthToDate, entries)
    val baselines =
        periods.baselineMonths.map { statementFor(sameDays(periods.today, it), entries) }

    fun mean(figure: (IncomeStatement) -> Money): Money? =
        if (baselines.isEmpty()) null else baselines.map(figure).sum().dividedBy(baselines.size)

    fun figure(amount: Money, baseline: Money?) =
        Figure(amount, baseline?.let { Comparison.of(amount, it) })

    val income = mean { it.income }
    val netIncome = mean { it.netIncome }
    val savingsRate = statement.savingsRate
    val savingsRateBaseline =
        if (income != null && netIncome != null) percentOf(income, netIncome) else null
    val savingsRateChange =
        if (savingsRate != null && savingsRateBaseline != null) savingsRate - savingsRateBaseline
        else null

    return MonthFigures(
        period = periods.monthToDate,
        income = figure(statement.income, income),
        expenses = figure(statement.expenses, mean { it.expenses }),
        netIncome = figure(statement.netIncome, netIncome),
        savingsRate = savingsRate,
        savingsRateBaseline = savingsRateBaseline,
        savingsRateChange = savingsRateChange,
        incomeLines = lines({ it.incomeLines }, statement, baselines, null),
        expenseLines =
            lines(
                { it.expenseLines },
                statement,
                baselines,
                percentOf(statement.expenses, Money.ZERO),
            ),
        baselineMonthCount = baselines.size,
        latestTransaction = entries.within(periods.monthToDate).maxOfOrNull { it.date },
    )
}

/**
 * Each history month's income statement to its closing date, and its position on that date, from
 * the same shared code as its monthly report.
 */
fun history(
    periods: DashboardPeriods,
    balanceHistory: BalanceSheetHistory,
    entries: List<Entry>,
): List<HistoryMonth> =
    periods.historyMonths.map { month ->
        val closing = closingDate(periods.today, month)
        val statement = statementFor(monthPeriod(periods.today, month), entries)
        val sheet = balanceHistory.asOf(closing).takeIf { it.hasKnownLines }
        HistoryMonth(
            month = month,
            closingDate = closing,
            complete = month.isComplete(periods.today),
            income = statement.income,
            expenses = statement.expenses,
            netIncome = statement.netIncome,
            netWorth = sheet?.netWorth,
            workingCapital = sheet?.workingCapital,
        )
    }

/** The baseline months' totals and monthly averages, or null when there are none. */
fun totals(periods: DashboardPeriods, history: List<HistoryMonth>): HistoryTotals? {
    val months = history.filter { it.month in periods.baselineMonths }
    if (months.isEmpty()) return null
    val income = months.map { it.income }.sum()
    val expenses = months.map { it.expenses }.sum()
    val netIncome = months.map { it.netIncome }.sum()
    return HistoryTotals(
        monthCount = months.size,
        income = income,
        expenses = expenses,
        netIncome = netIncome,
        savingsRate = percentOf(income, netIncome),
        averageIncome = income.dividedBy(months.size),
        averageExpenses = expenses.dividedBy(months.size),
        averageNetIncome = netIncome.dividedBy(months.size),
    )
}

/**
 * Working capital divided by the average monthly expenses, to one decimal place. Null without
 * totals or when the average is not positive; zero when working capital is negative.
 */
fun runway(workingCapital: Money, totals: HistoryTotals?): BigDecimal? {
    val expenses = totals?.averageExpenses?.takeIf { it > Money.ZERO } ?: return null
    return BigDecimal.valueOf(maxOf(Money.ZERO, workingCapital).cents)
        .divide(BigDecimal.valueOf(expenses.cents), 1, RoundingMode.HALF_UP)
}

/** The earliest as-of date among the sheet's lines with a known balance. */
private fun oldestAsOf(sheet: BalanceSheet): LocalDate? =
    (sheet.items.map { it.current.asOf } + sheet.accounts.mapNotNull { it.current?.asOf })
        .minOrNull()

/** Every figure on the dashboard, from the balance sheet history and the read period's entries. */
fun compute(
    periods: DashboardPeriods,
    balanceHistory: BalanceSheetHistory,
    entries: List<Entry>,
): DashboardFigures {
    val months = history(periods, balanceHistory, entries)
    val totals = totals(periods, months)
    val sheet = balanceHistory.asOf(periods.today)
    return DashboardFigures(
        position =
            Position(
                isEmpty = sheet.items.isEmpty() && sheet.accounts.isEmpty(),
                netWorth = sheet.netWorth,
                workingCapital = sheet.workingCapital,
                runway = runway(sheet.workingCapital, totals),
                oldestAsOf = oldestAsOf(sheet),
            ),
        month = month(periods, entries),
        history = months,
        totals = totals,
    )
}
