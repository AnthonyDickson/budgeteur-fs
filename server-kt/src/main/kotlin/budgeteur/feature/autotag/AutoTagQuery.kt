package budgeteur.feature.autotag

import budgeteur.data.CategorisationKind
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.toCategorisation
import budgeteur.domain.TransactionDescription
import org.jooq.DSLContext
import org.jooq.Record
import org.jooq.SelectConditionStep
import org.jooq.SelectSelectStep

/**
 * The user's transactions that may have a tag: every one but transfers. A transfer has no tag, so
 * rules never apply to one.
 */
private fun <R : Record> SelectSelectStep<R>.taggable(userId: String): SelectConditionStep<R> =
    from(TRANSACTIONS)
        .leftJoin(CATEGORISATIONS)
        .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
        .where(
            TRANSACTIONS.USER_ID.eq(userId),
            CATEGORISATIONS.KIND.isNull.or(
                CATEGORISATIONS.KIND.ne(CategorisationKind.Transfer.name)
            ),
        )

fun DSLContext.readCandidates(userId: String): List<Candidate> =
    select(TRANSACTIONS.ID, TRANSACTIONS.DESCRIPTION, *CATEGORISATIONS.fields())
        .taggable(userId)
        .fetch {
            Candidate(
                checkNotNull(it.get(TRANSACTIONS.ID)),
                TransactionDescription.unsafe(checkNotNull(it.get(TRANSACTIONS.DESCRIPTION))),
                if (it.get(CATEGORISATIONS.TRANSACTION_ID) == null) {
                    null
                } else {
                    it.into(CATEGORISATIONS).toCategorisation()
                },
            )
        }

/** The descriptions of the transactions that may have a tag, most recent first. */
fun DSLContext.readDescriptions(userId: String): List<TransactionDescription> =
    select(TRANSACTIONS.DESCRIPTION)
        .taggable(userId)
        .orderBy(TRANSACTIONS.DATE.desc(), TRANSACTIONS.ID.desc())
        .fetch { TransactionDescription.unsafe(checkNotNull(it.value1())) }
