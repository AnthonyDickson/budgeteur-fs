package budgeteur.data

import budgeteur.data.db.tables.records.AccountsRecord
import budgeteur.data.db.tables.records.BalanceObservationsRecord
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.BALANCE_OBSERVATIONS
import budgeteur.data.db.tables.references.CURRENT_BALANCES
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.domain.Account
import budgeteur.domain.AccountBalance
import budgeteur.domain.AccountName
import budgeteur.domain.AccountNumber
import budgeteur.domain.BalanceObservation
import budgeteur.domain.Money
import budgeteur.domain.Term
import budgeteur.domain.formatCalendarDate
import java.time.LocalDate
import java.util.UUID
import org.jooq.DSLContext
import org.jooq.Record

fun Account.toRecord(userId: String) =
    AccountsRecord(
        id = id,
        userId = userId,
        number = number?.value,
        name = name.value,
        term = term.name,
        closedOn = closedOn?.formatCalendarDate(),
    )

/** Every write parses its fields first, and the database checks the term and date. */
fun AccountsRecord.toAccount() =
    Account(
        id = id,
        number = number?.let(AccountNumber::unsafe),
        name = AccountName.unsafe(name),
        term = Term.valueOf(term),
        closedOn = closedOn?.let(LocalDate::parse),
    )

fun BalanceObservation.toRecord(accountId: UUID, userId: String) =
    BalanceObservationsRecord(
        accountId = accountId,
        userId = userId,
        asOf = asOf.formatCalendarDate(),
        balance = balance.cents,
    )

fun BalanceObservationsRecord.toObservation() =
    BalanceObservation(LocalDate.parse(asOf), Money(balance))

/**
 * An account row left joined to its row in [CURRENT_BALANCES]. The view's columns are nullable, so
 * an unmatched join and a missing column both read as an unknown balance.
 */
fun Record.toAccountBalance(): AccountBalance {
    val asOf = get(CURRENT_BALANCES.AS_OF)
    val balance = get(CURRENT_BALANCES.BALANCE)
    return AccountBalance(
        into(ACCOUNTS).toAccount(),
        if (asOf != null && balance != null) {
            BalanceObservation(LocalDate.parse(asOf), Money(balance))
        } else {
            null
        },
    )
}

/**
 * Records the account's balance as of the observation's date, replacing any on that date. Every
 * slice that records a balance writes through here, so statements and hand entries replace each
 * other the same way. The caller checks that the account belongs to the user.
 */
fun DSLContext.recordBalance(userId: String, accountId: UUID, observation: BalanceObservation) {
    val record = observation.toRecord(accountId, userId)
    insertInto(BALANCE_OBSERVATIONS)
        .set(record)
        .onConflict(BALANCE_OBSERVATIONS.ACCOUNT_ID, BALANCE_OBSERVATIONS.AS_OF)
        .doUpdate()
        .set(BALANCE_OBSERVATIONS.BALANCE, record.balance)
        .execute()
}

/**
 * The account and date of each of the user's transactions dated after its account's close date. A
 * closed account should have none. Transactions on the close date are its last, so they are not
 * included. Shared by the slices that flag them. See decision 4 in docs/reports.md.
 */
fun DSLContext.readTransactionsAfterClose(userId: String): List<Pair<UUID, LocalDate>> =
    select(ACCOUNTS.ID, TRANSACTIONS.DATE)
        .from(TRANSACTIONS)
        .join(ACCOUNTS)
        .on(ACCOUNTS.ID.eq(TRANSACTIONS.ACCOUNT_ID))
        .where(
            TRANSACTIONS.USER_ID.eq(userId),
            ACCOUNTS.USER_ID.eq(userId),
            // Text order is date order. A null close date compares as null, so open accounts drop
            // out.
            TRANSACTIONS.DATE.gt(ACCOUNTS.CLOSED_ON),
        )
        .fetch { checkNotNull(it.value1()) to LocalDate.parse(it.value2()) }
