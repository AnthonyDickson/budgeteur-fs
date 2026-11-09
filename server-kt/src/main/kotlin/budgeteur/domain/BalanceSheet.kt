package budgeteur.domain

import java.time.LocalDate

/**
 * The open items and accounts a user tracks: the two sources of lines. The sheet stores no date of
 * its own: each line carries its own as-of date. See decisions 4 and 5 in docs/balance-sheet.md.
 */
data class BalanceSheet(
    /** Every asset and liability that is not an account, with its current value. */
    val items: List<ItemValue>,
    /** Every account, whether its balance is known or not. */
    val accounts: List<AccountBalance>,
) {
    /** Where a line sits on the sheet and the magnitude it adds there. */
    private data class Line(val side: Side, val term: Term, val amount: Money)

    private val lines: List<Line>
        get() =
            items.map { Line(it.item.side, it.item.term, it.current.value.amount) } +
                accounts.mapNotNull { account ->
                    account.current?.let {
                        val (side, amount) = accountSide(it.balance)
                        Line(side, account.account.term, amount)
                    }
                }

    private fun total(side: Side, term: Term? = null): Money =
        lines
            .filter { it.side == side && (term == null || it.term == term) }
            .map { it.amount }
            .sum()

    /** The accounts whose balance is unknown, left out of the totals: unknown is not zero. */
    val unknownBalances: List<Account>
        get() = accounts.filter { it.current == null }.map { it.account }

    /** Everything owned, current and non-current. */
    val totalAssets: Money
        get() = total(Side.Asset)

    /** Everything owed, current and non-current. */
    val totalLiabilities: Money
        get() = total(Side.Liability)

    /** Assets expected to be realised within the current period. */
    val totalCurrentAssets: Money
        get() = total(Side.Asset, Term.Current)

    /** Liabilities expected to be settled within the current period. */
    val totalCurrentLiabilities: Money
        get() = total(Side.Liability, Term.Current)

    /** Assets **not** expected to be realised within the current period. */
    val totalNonCurrentAssets: Money
        get() = total(Side.Asset, Term.NonCurrent)

    /** Liabilities **not** expected to be settled within the current period. */
    val totalNonCurrentLiabilities: Money
        get() = total(Side.Liability, Term.NonCurrent)

    val netWorth: Money
        get() = totalAssets - totalLiabilities

    /** Whether any line has a known balance. A sheet without one has no meaningful totals. */
    val hasKnownLines: Boolean
        get() = items.isNotEmpty() || accounts.any { it.current != null }

    /**
     * Current assets minus current liabilities: the near-term position. Unlike net worth it
     * excludes non-current debt, so it stays sensitive to near-term decisions.
     */
    val workingCapital: Money
        get() = totalCurrentAssets - totalCurrentLiabilities

    companion object {
        /**
         * The side and magnitude of an account's balance: an asset when it is zero or more, a
         * liability when it is negative. An overdrawn chequing account is a current liability.
         */
        fun accountSide(balance: Money): Pair<Side, Money> =
            if (balance < Money.ZERO) Side.Liability to -balance else Side.Asset to balance
    }
}

/** Whether a line closed on [closedOn], if ever, is still held on [date]. */
private fun isOpenOn(date: LocalDate, closedOn: LocalDate?) = closedOn == null || date < closedOn

/**
 * Every item and account a user has, open or closed, each with its observation history in any
 * order: what a balance sheet for any statement date is drawn from. See decision 3 in
 * docs/reports.md.
 */
data class BalanceSheetHistory(
    val items: List<Pair<BalanceSheetItem, List<ItemObservation>>>,
    val accounts: List<Pair<Account, List<BalanceObservation>>>,
) {
    /** The as-of date of the earliest observation of any item or account, if any. */
    val firstObservation: LocalDate?
        get() =
            (items.flatMap { (_, observations) -> observations.map { it.asOf } } +
                    accounts.flatMap { (_, observations) -> observations.map { it.asOf } })
                .minOrNull()

    /**
     * The balance sheet drawn for a statement date. Each line's balance is its latest observation
     * on or before the date. A line enters the sheet at its first observation and leaves it on its
     * close date. An account with no observations at all has an unknown balance, as on the current
     * sheet. Balances between observations are not interpolated: a line keeps its latest value
     * until the next, and its as-of date shows how old it is. See decision 3 in docs/reports.md.
     */
    fun asOf(date: LocalDate): BalanceSheet =
        BalanceSheet(
            items =
                items
                    .filter { (item, _) -> isOpenOn(date, item.closedOn) }
                    .mapNotNull { (item, observations) ->
                        observations
                            .filter { it.asOf <= date }
                            .maxByOrNull { it.asOf }
                            ?.let { ItemValue(item, it) }
                    },
            accounts =
                accounts
                    .filter { (account, _) -> isOpenOn(date, account.closedOn) }
                    .mapNotNull { (account, observations) ->
                        val latest = observations.filter { it.asOf <= date }.maxByOrNull { it.asOf }
                        when {
                            observations.isEmpty() -> AccountBalance(account, null)
                            latest != null -> AccountBalance(account, latest)
                            else -> null
                        }
                    },
        )
}
