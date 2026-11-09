package budgeteur.data

import budgeteur.data.db.tables.records.BalanceSheetItemsRecord
import budgeteur.data.db.tables.records.ItemObservationsRecord
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.db.tables.references.CURRENT_ITEM_VALUES
import budgeteur.data.db.tables.references.ITEM_OBSERVATIONS
import budgeteur.domain.BalanceSheetItem
import budgeteur.domain.ItemName
import budgeteur.domain.ItemObservation
import budgeteur.domain.ItemValue
import budgeteur.domain.Magnitude
import budgeteur.domain.Money
import budgeteur.domain.Side
import budgeteur.domain.Term
import budgeteur.domain.formatCalendarDate
import java.time.LocalDate
import java.util.UUID
import org.jooq.DSLContext
import org.jooq.Record

fun BalanceSheetItem.toRecord(userId: String) =
    BalanceSheetItemsRecord(
        id = id,
        userId = userId,
        name = name.value,
        side = side.name,
        term = term.name,
        closedOn = closedOn?.formatCalendarDate(),
    )

/** Every write parses its fields first, and the database checks the side, term and date. */
fun BalanceSheetItemsRecord.toItem() =
    BalanceSheetItem(
        id = id,
        name = ItemName.unsafe(name),
        side = Side.valueOf(side),
        term = Term.valueOf(term),
        closedOn = closedOn?.let(LocalDate::parse),
    )

fun ItemObservation.toRecord(itemId: UUID, userId: String) =
    ItemObservationsRecord(
        itemId = itemId,
        userId = userId,
        asOf = asOf.formatCalendarDate(),
        value = value.amount.cents,
    )

/** The database checks that the value is not negative. */
fun ItemObservationsRecord.toObservation() =
    ItemObservation(LocalDate.parse(asOf), Magnitude.unsafe(Money(value)))

/**
 * An item row joined to its row in [CURRENT_ITEM_VALUES]. The view's columns are nullable to jOOQ,
 * but every item has an observation, and the view reads them from columns that require them.
 */
fun Record.toItemValue(): ItemValue {
    val item = into(BALANCE_SHEET_ITEMS).toItem()
    val asOf = checkNotNull(get(CURRENT_ITEM_VALUES.AS_OF)) { "Item ${item.id} has no value" }
    val value = checkNotNull(get(CURRENT_ITEM_VALUES.VALUE)) { "Item ${item.id} has no value" }
    return ItemValue(item, ItemObservation(LocalDate.parse(asOf), Magnitude.unsafe(Money(value))))
}

/**
 * Records the item's value as of the observation's date, replacing any on that date. The caller
 * checks that the item belongs to the user.
 */
fun DSLContext.recordItemValue(userId: String, itemId: UUID, observation: ItemObservation) {
    val record = observation.toRecord(itemId, userId)
    insertInto(ITEM_OBSERVATIONS)
        .set(record)
        .onConflict(ITEM_OBSERVATIONS.ITEM_ID, ITEM_OBSERVATIONS.AS_OF)
        .doUpdate()
        .set(ITEM_OBSERVATIONS.VALUE, record.value)
        .execute()
}
