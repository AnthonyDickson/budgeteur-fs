package budgeteur.feature.report

import budgeteur.domain.Account
import budgeteur.domain.BalanceSheet
import budgeteur.domain.BalanceSheetHistory
import budgeteur.domain.Entry
import budgeteur.domain.Frequency
import budgeteur.domain.IncomeStatement
import budgeteur.domain.Money
import budgeteur.domain.Period
import budgeteur.domain.ReportingPeriod
import java.time.LocalDate
import java.util.UUID

/** How the position changed over a report's period, and how much of it was saved. */
data class Change(
    /** Closing net worth minus opening net worth. */
    val netWorth: Money,
    /**
     * The change net income does not explain: revaluations, money that never passes through a
     * tracked account, and missing transactions.
     */
    val otherChanges: Money,
    /** Closing working capital minus opening working capital. */
    val workingCapital: Money,
)

/**
 * The periods of a frequency that have reports: from the one containing the user's first
 * observation or transaction to the one containing today. See decision 5 in docs/reports.md.
 */
data class ReportRange(
    val first: ReportingPeriod,
    /** The period containing today, which is to date. */
    val current: ReportingPeriod,
) {
    operator fun contains(period: ReportingPeriod) = period.from in first.from..current.from
}

/** The position and performance for one reporting period. See docs/reports.md. */
data class Report(
    val period: ReportingPeriod,
    /** The closing sheet's statement date: the period's last day, or today for a report to date. */
    val closingDate: LocalDate,
    val complete: Boolean,
    val opening: BalanceSheet,
    val closing: BalanceSheet,
    /** Null when the opening sheet has no lines, where the change would be the whole position. */
    val change: Change?,
    val incomeStatement: IncomeStatement,
    /**
     * Closed accounts with transactions in the income statement's dates that are after their close
     * date. The statement counts those transactions, but the balance sheets leave the accounts out,
     * so other changes are off by their net amount. See decision 4 in docs/reports.md.
     */
    val closedAccountsWithTransactions: List<Account>,
    val hasPrevious: Boolean,
    val hasNext: Boolean,
)

/** The periods of the frequency that have reports. A user with no data has today's period only. */
fun range(frequency: Frequency, today: LocalDate, firstDate: LocalDate?): ReportRange =
    ReportRange(
        ReportingPeriod.containing(frequency, firstDate?.let { minOf(it, today) } ?: today),
        ReportingPeriod.containing(frequency, today),
    )

/**
 * The period to report on: the one containing [date], or with no date the latest complete period,
 * falling back to the period to date when no complete one has data. Null when the date is outside
 * the range.
 */
fun period(range: ReportRange, date: LocalDate?): ReportingPeriod? =
    if (date != null) {
        ReportingPeriod.containing(range.current.frequency, date).takeIf { it in range }
    } else {
        range.current.previous().takeIf { it in range } ?: range.current
    }

/** The earliest date the user has data for: their first observation or transaction. */
fun firstDate(history: BalanceSheetHistory, firstTransaction: LocalDate?): LocalDate? =
    listOfNotNull(firstTransaction, history.firstObservation).minOrNull()

/**
 * The closing sheet's statement date: the period's last day once it is complete, otherwise the
 * client's today. The income statement runs to the same date.
 */
fun closingDate(today: LocalDate, period: ReportingPeriod): LocalDate =
    if (period.isComplete(today)) period.to else today

/** The income statement period: the period's first day to the closing date. */
fun statementPeriod(today: LocalDate, period: ReportingPeriod) =
    Period(period.from, closingDate(today, period))

/**
 * The report for a period of the range, from the user's balance sheet history and the period's
 * income statement entries, which run from its first day to the closing date.
 * [transactionsAfterClose] are the account and date of each transaction dated after its account's
 * close date.
 */
fun compute(
    today: LocalDate,
    range: ReportRange,
    period: ReportingPeriod,
    history: BalanceSheetHistory,
    entries: List<Entry>,
    transactionsAfterClose: List<Pair<UUID, LocalDate>>,
): Report {
    val closingDate = closingDate(today, period)
    val opening = history.asOf(period.from.minusDays(1))
    val closing = history.asOf(closingDate)
    val statementPeriod = statementPeriod(today, period)
    val statement = IncomeStatement.compute(statementPeriod, entries)

    val lateAccountIds =
        transactionsAfterClose
            .filter { (_, date) -> date in statementPeriod }
            .map { it.first }
            .toSet()

    val change =
        if (opening.hasKnownLines) {
            val netWorth = closing.netWorth - opening.netWorth
            Change(
                netWorth = netWorth,
                otherChanges = netWorth - statement.netIncome,
                workingCapital = closing.workingCapital - opening.workingCapital,
            )
        } else {
            null
        }

    return Report(
        period = period,
        closingDate = closingDate,
        complete = period.isComplete(today),
        opening = opening,
        closing = closing,
        change = change,
        incomeStatement = statement,
        closedAccountsWithTransactions =
            history.accounts.map { it.first }.filter { it.id in lateAccountIds },
        hasPrevious = period != range.first,
        hasNext = period != range.current,
    )
}
