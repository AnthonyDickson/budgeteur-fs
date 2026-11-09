package budgeteur.feature.transaction

import budgeteur.data.CategorisationKind
import budgeteur.data.containsPattern
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.toCategorisation
import budgeteur.data.toTransaction
import budgeteur.data.withPatternMatch
import budgeteur.domain.Categorisation
import budgeteur.domain.Transaction
import budgeteur.domain.formatCalendarDate
import java.util.UUID
import org.jooq.Condition
import org.jooq.DSLContext
import org.jooq.Record
import org.jooq.SelectOnConditionStep

/**
 * The slice's read shape: a transaction with its categorisation, if any, and its account's name, if
 * any. Writes respond with it too, read back inside their database transaction, so every response
 * carries the same fields.
 */
data class TransactionDetails(
    val transaction: Transaction,
    val categorisation: Categorisation?,
    val accountName: String?,
)

private fun DSLContext.selectDetails(): SelectOnConditionStep<Record> =
    select(TRANSACTIONS.fields().toList() + CATEGORISATIONS.fields() + ACCOUNTS.NAME)
        .from(TRANSACTIONS)
        .leftJoin(CATEGORISATIONS)
        .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
        .leftJoin(ACCOUNTS)
        .on(ACCOUNTS.ID.eq(TRANSACTIONS.ACCOUNT_ID))

/** A left join leaves every column of an unmatched categorisation null. */
private fun Record.toDetails() =
    TransactionDetails(
        into(TRANSACTIONS).toTransaction(),
        if (get(CATEGORISATIONS.TRANSACTION_ID) == null) null
        else into(CATEGORISATIONS).toCategorisation(),
        get(ACCOUNTS.NAME),
    )

fun DSLContext.findTransaction(userId: String, id: UUID): TransactionDetails? =
    selectDetails()
        .where(TRANSACTIONS.ID.eq(id), TRANSACTIONS.USER_ID.eq(userId))
        .fetchOne()
        ?.toDetails()

fun DSLContext.readAllTransactions(userId: String): List<TransactionDetails> =
    selectDetails().where(TRANSACTIONS.USER_ID.eq(userId)).fetch { it.toDetails() }

private fun Search.conditions(): List<Condition> = buildList {
    text?.let { add(containsPattern(TRANSACTIONS.DESCRIPTION, it)) }
    from?.let { add(TRANSACTIONS.DATE.ge(it.formatCalendarDate())) }
    to?.let { add(TRANSACTIONS.DATE.le(it.formatCalendarDate())) }
    when (val account = account) {
        AccountCriterion.Any -> {}
        AccountCriterion.NoAccount -> add(TRANSACTIONS.ACCOUNT_ID.isNull)
        is AccountCriterion.Account -> add(TRANSACTIONS.ACCOUNT_ID.eq(account.id))
    }
    val untagged = CATEGORISATIONS.TRANSACTION_ID.isNull
    val dismissed = CATEGORISATIONS.KIND.eq(CategorisationKind.Dismissed.name)
    when (val tag = tag) {
        TagCriterion.Any -> {}
        TagCriterion.WithoutTag -> add(untagged.or(dismissed))
        TagCriterion.Untagged -> add(untagged)
        TagCriterion.Dismissed -> add(dismissed)
        TagCriterion.Transfer -> add(CATEGORISATIONS.KIND.eq(CategorisationKind.Transfer.name))
        is TagCriterion.Tag -> add(CATEGORISATIONS.TAG_ID.eq(tag.id))
    }
    when (direction) {
        Direction.Any -> {}
        Direction.Credit -> add(TRANSACTIONS.AMOUNT.gt(0))
        Direction.Debit -> add(TRANSACTIONS.AMOUNT.lt(0))
    }
    // A size bounds the absolute amount, so each bound is a pair of signed comparisons. SQLite's
    // abs() would overflow on the smallest INTEGER.
    minimum?.let { add(TRANSACTIONS.AMOUNT.ge(it.cents).or(TRANSACTIONS.AMOUNT.le(-it.cents))) }
    maximum?.let { add(TRANSACTIONS.AMOUNT.le(it.cents).and(TRANSACTIONS.AMOUNT.ge(-it.cents))) }
}

/** Matches after [after], newest first, then by id. */
private fun Cursor?.condition(): Condition? =
    this?.let {
        val date = it.date.formatCalendarDate()
        TRANSACTIONS.DATE.lt(date).or(TRANSACTIONS.DATE.eq(date).and(TRANSACTIONS.ID.lt(it.id)))
    }

/**
 * A page of the user's transactions matching [search], starting after [after], and the cursor for
 * the next page. See docs/transaction-search.md.
 */
fun DSLContext.searchTransactions(
    userId: String,
    search: Search,
    after: Cursor?,
): Pair<List<TransactionDetails>, Cursor?> = withPatternMatch {
    val matches =
        selectDetails()
            .where(
                listOfNotNull(TRANSACTIONS.USER_ID.eq(userId), after.condition()) +
                    search.conditions()
            )
            .orderBy(TRANSACTIONS.DATE.desc(), TRANSACTIONS.ID.desc())
            .limit(PAGE_SIZE + 1)
            .fetch { it.toDetails() }
    page(matches) { Cursor(it.transaction.date, it.transaction.id) }
}
