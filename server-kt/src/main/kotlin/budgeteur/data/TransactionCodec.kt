package budgeteur.data

import budgeteur.data.db.tables.records.TransactionsRecord
import budgeteur.domain.Money
import budgeteur.domain.Transaction
import budgeteur.domain.TransactionDescription
import budgeteur.domain.formatCalendarDate
import java.time.LocalDate

fun Transaction.toRecord(userId: String, importHash: String? = null) =
    TransactionsRecord(
        id = id,
        userId = userId,
        amount = amount.cents,
        description = description.value,
        date = date.formatCalendarDate(),
        accountId = accountId,
        importHash = importHash,
    )

/** Every write parses its fields first, and the database checks the date. */
fun TransactionsRecord.toTransaction(): Transaction =
    Transaction(
        id = id,
        amount = Money(amount),
        description = TransactionDescription.unsafe(description),
        date = LocalDate.parse(date),
        accountId = accountId,
    )
