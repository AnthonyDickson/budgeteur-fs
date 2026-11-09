package budgeteur.domain

import java.time.LocalDate

/** How long a reporting period is. See decision 5 in docs/reports.md. */
enum class Frequency {
    Monthly,

    /** Calendar quarters, which are also the quarters of a financial year from 1 April. */
    Quarterly,
    CalendarYear,

    /** 1 April to 31 March. */
    FinancialYear,
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

    companion object {
        /** The month a financial year starts in. */
        const val FINANCIAL_YEAR_START = 4

        private const val MONTHS_IN_QUARTER = 3
        private const val MONTHS_IN_YEAR = 12

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
