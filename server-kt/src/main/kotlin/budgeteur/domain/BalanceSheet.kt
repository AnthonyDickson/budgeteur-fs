package budgeteur.domain

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
