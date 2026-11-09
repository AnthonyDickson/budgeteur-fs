package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** How long a reporting period is. See decision 5 in docs/reports.md. */
enum class Frequency {
    Monthly,

    /** Calendar quarters, which are also the quarters of a financial year from 1 April. */
    Quarterly,
    CalendarYear,

    /** 1 April to 31 March. */
    FinancialYear;

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): Frequency =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for Frequency, expecting one of \"Monthly\", " +
                    "\"Quarterly\", \"CalendarYear\", or \"FinancialYear\"."
            }
    }
}

/**
 * A period aligned to its frequency: a calendar month, a quarter, a calendar year, or a financial
 * year. Only [containing] makes one, so its days are always aligned.
 */
@ConsistentCopyVisibility
data class ReportingPeriod
private constructor(val frequency: Frequency, val from: LocalDate, val to: LocalDate) {
    /** The period before, of the same frequency. */
    fun previous() = containing(frequency, from.minusDays(1))

    /** The period after, of the same frequency. */
    fun next() = containing(frequency, to.plusDays(1))

    /**
     * Whether the period's last day is on or before the client's [today]. A report for a period
     * that is not complete is to date.
     */
    fun isComplete(today: LocalDate) = to <= today

    /**
     * The period's name, e.g. "March 2026", "Q1 2026", "2026", or "2026/27" for a financial year.
     */
    val label: String
        get() =
            when (frequency) {
                Frequency.Monthly -> from.format(monthLabel)
                Frequency.Quarterly ->
                    "Q${(from.monthValue - 1) / MONTHS_IN_QUARTER + 1} ${from.year}"
                Frequency.CalendarYear -> "${from.year}"
                Frequency.FinancialYear -> "${from.year}/%02d".format((from.year + 1) % 100)
            }

    companion object {
        /** The month a financial year starts in. */
        const val FINANCIAL_YEAR_START = 4

        private const val MONTHS_IN_QUARTER = 3
        private const val MONTHS_IN_YEAR = 12

        private val monthLabel = DateTimeFormatter.ofPattern("MMMM uuuu", Locale.ENGLISH)

        /** The period of the frequency that contains [date]. */
        fun containing(frequency: Frequency, date: LocalDate): ReportingPeriod {
            fun months(year: Int, month: Int, count: Long): ReportingPeriod {
                val from = LocalDate.of(year, month, 1)
                return ReportingPeriod(frequency, from, from.plusMonths(count).minusDays(1))
            }

            val quarterStart = (date.monthValue - 1) / MONTHS_IN_QUARTER * MONTHS_IN_QUARTER + 1
            return when (frequency) {
                Frequency.Monthly -> months(date.year, date.monthValue, 1)
                Frequency.Quarterly -> months(date.year, quarterStart, MONTHS_IN_QUARTER.toLong())
                Frequency.CalendarYear -> months(date.year, 1, MONTHS_IN_YEAR.toLong())
                Frequency.FinancialYear -> {
                    val year =
                        if (date.monthValue >= FINANCIAL_YEAR_START) date.year else date.year - 1
                    months(year, FINANCIAL_YEAR_START, MONTHS_IN_YEAR.toLong())
                }
            }
        }
    }
}
