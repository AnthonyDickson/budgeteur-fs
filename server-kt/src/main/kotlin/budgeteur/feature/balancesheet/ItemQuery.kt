package budgeteur.feature.balancesheet

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.db.tables.references.CURRENT_ITEM_VALUES
import budgeteur.data.toItemValue
import budgeteur.domain.BalanceSheetItem
import budgeteur.domain.ItemValue
import java.util.UUID
import org.jooq.DSLContext
import org.jooq.impl.DSL

/** The user's items, or only the one with [id], with their current values. */
private fun DSLContext.readItems(userId: String, id: UUID? = null): List<ItemValue> =
    select(
            BALANCE_SHEET_ITEMS.fields().toList() +
                CURRENT_ITEM_VALUES.AS_OF +
                CURRENT_ITEM_VALUES.VALUE
        )
        .from(BALANCE_SHEET_ITEMS)
        .join(CURRENT_ITEM_VALUES)
        .on(CURRENT_ITEM_VALUES.ITEM_ID.eq(BALANCE_SHEET_ITEMS.ID))
        .where(
            BALANCE_SHEET_ITEMS.USER_ID.eq(userId),
            id?.let(BALANCE_SHEET_ITEMS.ID::eq) ?: DSL.noCondition(),
        )
        .orderBy(BALANCE_SHEET_ITEMS.NAME)
        .fetch { it.toItemValue() }

fun DSLContext.readAllItems(userId: String): List<ItemValue> = readItems(userId)

fun DSLContext.findItem(userId: String, id: UUID): ItemValue? = readItems(userId, id).singleOrNull()

fun DSLContext.itemExists(userId: String, id: UUID): Boolean =
    fetchExists(
        BALANCE_SHEET_ITEMS,
        BALANCE_SHEET_ITEMS.ID.eq(id),
        BALANCE_SHEET_ITEMS.USER_ID.eq(userId),
    )

/** The `UNIQUE (user_id, name, side, term)` constraint, ignoring the item itself. */
context(_: Raise<ConstraintError>)
fun DSLContext.requireUniqueItem(userId: String, item: BalanceSheetItem) =
    ensure(
        !fetchExists(
            BALANCE_SHEET_ITEMS,
            BALANCE_SHEET_ITEMS.USER_ID.eq(userId),
            BALANCE_SHEET_ITEMS.NAME.eq(item.name.value),
            BALANCE_SHEET_ITEMS.SIDE.eq(item.side.name),
            BALANCE_SHEET_ITEMS.TERM.eq(item.term.name),
            BALANCE_SHEET_ITEMS.ID.ne(item.id),
        )
    ) {
        ConstraintError("An identical balance sheet item already exists.")
    }
