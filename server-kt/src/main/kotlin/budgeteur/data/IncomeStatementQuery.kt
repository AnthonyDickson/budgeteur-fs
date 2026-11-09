package budgeteur.data

import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.domain.Entry
import budgeteur.domain.Money
import budgeteur.domain.Period
import budgeteur.domain.formatCalendarDate
import java.time.LocalDate
import org.jooq.DSLContext
import org.jooq.impl.DSL

// The reads an income statement is computed from, shared by the slices that compute one.

/** The user's non-transfer transactions in the period, each with its tag. */
fun DSLContext.readEntries(userId: String, period: Period): List<Entry> {
    val tags =
        selectFrom(TAGS).where(TAGS.USER_ID.eq(userId)).fetch { it.toTag() }.associateBy { it.id }
    return select(TRANSACTIONS.DATE, TRANSACTIONS.AMOUNT, CATEGORISATIONS.TAG_ID)
        .from(TRANSACTIONS)
        .leftJoin(CATEGORISATIONS)
        .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
        .where(
            TRANSACTIONS.USER_ID.eq(userId),
            // Text order is date order.
            TRANSACTIONS.DATE.between(
                period.from.formatCalendarDate(),
                period.to.formatCalendarDate(),
            ),
            CATEGORISATIONS.KIND.isNull.or(
                CATEGORISATIONS.KIND.ne(CategorisationKind.Transfer.name)
            ),
        )
        .fetch { (date, amount, tagId) ->
            Entry(LocalDate.parse(date), Money(checkNotNull(amount)), tagId?.let(tags::get))
        }
}

/** The date of the user's earliest transaction, if any. */
fun DSLContext.readFirstTransactionDate(userId: String): LocalDate? =
    select(DSL.min(TRANSACTIONS.DATE))
        .from(TRANSACTIONS)
        .where(TRANSACTIONS.USER_ID.eq(userId))
        .fetchOne()
        ?.value1()
        ?.let(LocalDate::parse)
