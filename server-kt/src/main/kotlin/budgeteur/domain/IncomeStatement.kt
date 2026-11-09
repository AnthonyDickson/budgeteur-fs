package budgeteur.domain

import java.math.BigDecimal
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * An inclusive range of calendar dates, at most [MAX_DAYS] long. Built only from dates the server
 * derives, so a bad one is a bug and throws.
 */
data class Period(val from: LocalDate, val to: LocalDate) {
    init {
        require(from <= to) { "'from' ($from) must not be after 'to' ($to)" }
        val days = ChronoUnit.DAYS.between(from, to) + 1
        require(days <= MAX_DAYS) { "A period can span at most $MAX_DAYS days, got $days" }
    }

    operator fun contains(date: LocalDate) = date in from..to

    companion object {
        /**
         * Two years, one of them a leap year. Long enough for the dashboard's history, which spans
         * up to thirteen months.
         */
        const val MAX_DAYS = 731
    }
}

/**
 * A non-transfer transaction with its date and its tag, if it has one. The income statement ignores
 * the date; it lets one read be split into several periods.
 */
data class Entry(val date: LocalDate, val amount: Money, val tag: Tag?)

/**
 * One tag's net amount for the period, or the untagged income or expenses (`tag` null). Income
 * lines are amounts received; expense lines are amounts spent. [share] is an expense line's
 * percentage of total expenses, null for income lines and when expenses are zero or negative.
 */
data class StatementLine(val tag: Tag?, val amount: Money, val share: BigDecimal? = null)

/** Largest amount first, with the untagged line last. Ties are broken by name. */
val statementLineOrder: Comparator<StatementLine> =
    compareBy<StatementLine> { it.tag == null }
        .thenByDescending { it.amount }
        .thenBy { it.tag?.name?.value.orEmpty() }

/** Income, expenses, and net income for a period. See docs/dashboard.md. */
data class IncomeStatement(
    val period: Period,
    val income: Money,
    val expenses: Money,
    val incomeLines: List<StatementLine>,
    val expenseLines: List<StatementLine>,
) {
    val netIncome: Money
        get() = income - expenses

    /**
     * Net income as a percentage of income, or null when income is zero or negative. It is on
     * take-home pay, since the app sees bank transactions. See decision 13 in docs/dashboard.md.
     */
    val savingsRate: BigDecimal?
        get() = percentOf(income, netIncome)

    companion object {
        /**
         * The statement of the period's non-transfer transactions. Each tag's transactions are
         * netted, and the tag's kind decides the side whatever the sign of the net: a refund
         * reduces its expense tag, possibly below zero, rather than counting as income. Untagged
         * transactions have no kind, so they are split by sign into untagged income and expenses.
         */
        fun compute(period: Period, entries: List<Entry>): IncomeStatement {
            val nets =
                entries
                    .filter { it.tag != null }
                    .groupBy({ checkNotNull(it.tag) }) { it.amount }
                    .mapValues { (_, amounts) -> amounts.sum() }
            val untagged = entries.filter { it.tag == null }.map { it.amount }

            fun untaggedLine(amounts: List<Money>, sign: Int): List<StatementLine> =
                if (amounts.isEmpty()) emptyList()
                else listOf(StatementLine(null, amounts.sum().let { if (sign < 0) -it else it }))

            val incomeLines =
                (nets
                        .filterKeys { it.kind == TagKind.Income }
                        .map { (tag, net) -> StatementLine(tag, net) } +
                        untaggedLine(untagged.filter { it > Money.ZERO }, 1))
                    .sortedWith(statementLineOrder)
            val expenseLines =
                (nets
                        .filterKeys { it.kind == TagKind.Expense }
                        .map { (tag, net) -> StatementLine(tag, -net) } +
                        untaggedLine(untagged.filter { it < Money.ZERO }, -1))
                    .sortedWith(statementLineOrder)
            val income = incomeLines.map { it.amount }.sum()
            val expenses = expenseLines.map { it.amount }.sum()
            return IncomeStatement(
                period,
                income,
                expenses,
                incomeLines,
                expenseLines.map { it.copy(share = percentOf(expenses, it.amount)) },
            )
        }
    }
}
