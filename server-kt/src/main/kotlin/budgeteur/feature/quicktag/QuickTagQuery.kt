package budgeteur.feature.quicktag

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.saveCategorisation
import budgeteur.data.toTag
import budgeteur.data.toTransaction
import budgeteur.domain.Categorisation
import budgeteur.domain.Tag
import budgeteur.domain.Transaction
import budgeteur.shared.DomainError
import java.util.UUID
import org.jooq.DSLContext

/** The most a queue read returns, and the most an approval may list. */
const val BATCH_SIZE = 50

/** A queued transaction and its account's name, if it has one. */
data class Queued(val transaction: Transaction, val accountName: String?)

/**
 * The user's whole queue: transactions without a categorisation, which excludes dismissed ones and
 * transfers, newest first, with their account names. Every queued transaction is suggested and
 * counted, not only the batch. See decision 2 in docs/quick-tagging.md.
 */
fun DSLContext.readQueued(userId: String): List<Queued> =
    select(TRANSACTIONS.fields().toList() + ACCOUNTS.NAME)
        .from(TRANSACTIONS)
        .leftJoin(CATEGORISATIONS)
        .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
        .leftJoin(ACCOUNTS)
        .on(ACCOUNTS.ID.eq(TRANSACTIONS.ACCOUNT_ID))
        .where(TRANSACTIONS.USER_ID.eq(userId), CATEGORISATIONS.TRANSACTION_ID.isNull)
        .orderBy(TRANSACTIONS.DATE.desc(), TRANSACTIONS.ID.desc())
        .fetch { Queued(it.into(TRANSACTIONS).toTransaction(), it.get(ACCOUNTS.NAME)) }

fun DSLContext.readTags(userId: String): List<Tag> =
    selectFrom(TAGS).where(TAGS.USER_ID.eq(userId)).fetch { it.toTag() }

/**
 * The write the quick tagging operations share: sets one of the user's transactions'
 * categorisation, replacing whatever it had. Raises not found when the user has no transaction with
 * the id. Run it inside the write's database transaction; the caller checks that a tag belongs to
 * the user.
 */
context(_: Raise<DomainError>)
fun DSLContext.saveChoice(userId: String, transactionId: UUID, categorisation: Categorisation) {
    ensure(
        fetchExists(
            TRANSACTIONS,
            TRANSACTIONS.ID.eq(transactionId),
            TRANSACTIONS.USER_ID.eq(userId),
        )
    ) {
        DomainError.NotFound("Transaction $transactionId not found")
    }
    saveCategorisation(userId, transactionId, categorisation)
}
