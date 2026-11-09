package budgeteur.feature.account

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.CURRENT_BALANCES
import budgeteur.data.readTransactionsAfterClose
import budgeteur.data.toAccountBalance
import budgeteur.domain.Account
import budgeteur.domain.AccountBalance
import budgeteur.domain.TransactionsAfterClose
import java.util.UUID
import org.jooq.DSLContext
import org.jooq.impl.DSL

/**
 * The slice's read shape: an account with its current balance and any transactions dated after its
 * close date. Writes respond with it too, read back inside their database transaction.
 */
data class AccountDetails(
    val balance: AccountBalance,
    val transactionsAfterClose: TransactionsAfterClose?,
)

/** The user's accounts, or only the one with [id], with their current balances, by name. */
private fun DSLContext.readDetails(userId: String, id: UUID? = null): List<AccountDetails> {
    val accounts =
        select(ACCOUNTS.fields().toList() + CURRENT_BALANCES.AS_OF + CURRENT_BALANCES.BALANCE)
            .from(ACCOUNTS)
            .leftJoin(CURRENT_BALANCES)
            .on(CURRENT_BALANCES.ACCOUNT_ID.eq(ACCOUNTS.ID))
            .where(ACCOUNTS.USER_ID.eq(userId), id?.let(ACCOUNTS.ID::eq) ?: DSL.noCondition())
            .orderBy(ACCOUNTS.NAME)
            .fetch { it.toAccountBalance() }
    if (accounts.isEmpty()) return emptyList()

    val afterClose =
        readTransactionsAfterClose(userId).groupBy({ (accountId, _) -> accountId }) { it.second }
    return accounts.map {
        AccountDetails(it, afterClose[it.account.id]?.let(TransactionsAfterClose::of))
    }
}

fun DSLContext.readAllAccounts(userId: String): List<AccountDetails> = readDetails(userId)

fun DSLContext.findAccount(userId: String, id: UUID): AccountDetails? =
    readDetails(userId, id).singleOrNull()

fun DSLContext.accountExists(userId: String, id: UUID): Boolean =
    fetchExists(ACCOUNTS, ACCOUNTS.ID.eq(id), ACCOUNTS.USER_ID.eq(userId))

/** The `UNIQUE (user_id, number)` constraint, ignoring the account itself. */
context(_: Raise<ConstraintError>)
fun DSLContext.requireUniqueNumber(userId: String, account: Account) {
    val number = account.number ?: return
    ensure(
        !fetchExists(
            ACCOUNTS,
            ACCOUNTS.USER_ID.eq(userId),
            ACCOUNTS.NUMBER.eq(number.value),
            ACCOUNTS.ID.ne(account.id),
        )
    ) {
        ConstraintError("Another account already has the number ${number.value}.")
    }
}
