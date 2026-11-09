package budgeteur.data

import budgeteur.data.db.tables.records.CategorisationsRecord
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.domain.Categorisation
import budgeteur.domain.Source
import java.util.UUID
import org.jooq.DSLContext

/** The values of `categorisations.kind`. Queries that filter by kind compare against them. */
enum class CategorisationKind {
    Tagged,
    Dismissed,
    Transfer,
}

fun Categorisation.toRecord(transactionId: UUID, userId: String): CategorisationsRecord {
    val kind =
        when (this) {
            is Categorisation.Tagged -> CategorisationKind.Tagged
            Categorisation.Dismissed -> CategorisationKind.Dismissed
            is Categorisation.Transfer -> CategorisationKind.Transfer
        }
    return CategorisationsRecord(
        transactionId = transactionId,
        userId = userId,
        kind = kind.name,
        tagId = (this as? Categorisation.Tagged)?.tagId,
        source = source.name,
    )
}

/** The database checks the kind, the source, and that only a tagged row has a tag. */
fun CategorisationsRecord.toCategorisation(): Categorisation {
    val source = Source.valueOf(source)
    return when (CategorisationKind.valueOf(kind)) {
        CategorisationKind.Tagged -> Categorisation.Tagged(checkNotNull(tagId), source)
        CategorisationKind.Dismissed -> Categorisation.Dismissed
        CategorisationKind.Transfer -> Categorisation.Transfer(source)
    }
}

/**
 * Sets a transaction's categorisation: inserts or replaces it, or deletes it when the transaction
 * is untagged. Every slice that categorises writes through here, so a categorisation is written one
 * way. The caller checks that the transaction and tag belong to the user.
 */
fun DSLContext.saveCategorisation(
    userId: String,
    transactionId: UUID,
    categorisation: Categorisation?,
) {
    if (categorisation == null) {
        deleteFrom(CATEGORISATIONS)
            .where(
                CATEGORISATIONS.TRANSACTION_ID.eq(transactionId),
                CATEGORISATIONS.USER_ID.eq(userId),
            )
            .execute()
    } else {
        val record = categorisation.toRecord(transactionId, userId)
        insertInto(CATEGORISATIONS)
            .set(record)
            .onConflict(CATEGORISATIONS.TRANSACTION_ID)
            .doUpdate()
            .set(CATEGORISATIONS.KIND, record.kind)
            .set(CATEGORISATIONS.TAG_ID, record.tagId)
            .set(CATEGORISATIONS.SOURCE, record.source)
            .execute()
    }
}
