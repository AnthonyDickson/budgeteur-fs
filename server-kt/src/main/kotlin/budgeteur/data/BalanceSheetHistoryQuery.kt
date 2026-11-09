package budgeteur.data

import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.BALANCE_OBSERVATIONS
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.db.tables.references.ITEM_OBSERVATIONS
import budgeteur.domain.BalanceSheetHistory
import org.jooq.DSLContext

/**
 * The user's items and accounts, open or closed, each with its observations: what a balance sheet
 * for any statement date is drawn from. A user's observations are few enough to load at once.
 * Shared by the slices that draw one.
 */
fun DSLContext.readBalanceSheetHistory(userId: String): BalanceSheetHistory {
    val itemObservations =
        selectFrom(ITEM_OBSERVATIONS).where(ITEM_OBSERVATIONS.USER_ID.eq(userId)).fetch().groupBy({
            it.itemId
        }) {
            it.toObservation()
        }
    val balanceObservations =
        selectFrom(BALANCE_OBSERVATIONS)
            .where(BALANCE_OBSERVATIONS.USER_ID.eq(userId))
            .fetch()
            .groupBy({ it.accountId }) { it.toObservation() }
    return BalanceSheetHistory(
        items =
            selectFrom(BALANCE_SHEET_ITEMS).where(BALANCE_SHEET_ITEMS.USER_ID.eq(userId)).fetch {
                it.toItem() to itemObservations[it.id].orEmpty()
            },
        accounts =
            selectFrom(ACCOUNTS).where(ACCOUNTS.USER_ID.eq(userId)).orderBy(ACCOUNTS.NAME).fetch {
                it.toAccount() to balanceObservations[it.id].orEmpty()
            },
    )
}
