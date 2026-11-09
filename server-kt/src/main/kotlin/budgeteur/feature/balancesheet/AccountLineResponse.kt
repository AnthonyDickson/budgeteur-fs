@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.balancesheet

import budgeteur.domain.Account
import budgeteur.domain.AccountBalance
import budgeteur.domain.BalanceSheet
import budgeteur.domain.Side
import budgeteur.domain.Term
import budgeteur.domain.TransactionsAfterClose
import budgeteur.domain.formatCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

// How accounts appear on the balance sheet. The account slice has its own account responses: the
// two change for different reasons.

private const val ACCOUNT_NAME = "The user's alias for the account."
private const val ACCOUNT_NUMBER = "The number statements identify the account by, if any."
private const val ACCOUNT_TERM = "Whether the account is current or non-current."

@Serializable
@JsonSchema.Description(
    "An account with a known balance, as a balance sheet line. Its side follows the sign of its " +
        "current balance."
)
data class AccountLineResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(ACCOUNT_NAME) val name: String,
    @JsonSchema.Description(ACCOUNT_NUMBER) val number: String?,
    @JsonSchema.Description(
        "Asset when the balance is zero or more, liability when it is negative."
    )
    @EnumOf(Side::class)
    val side: String,
    @JsonSchema.Description(ACCOUNT_TERM) @EnumOf(Term::class) val term: String,
    @JsonSchema.Description(
        "The magnitude of the current balance. Direction is implied by the side."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val balance: String,
    @JsonSchema.Description("The date the current balance is accurate as of.")
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
)

@Serializable
@JsonSchema.Description(
    "An account whose balance is unknown: it has no observations. It is left out of the totals."
)
data class UnknownBalanceResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(ACCOUNT_NAME) val name: String,
    @JsonSchema.Description(ACCOUNT_NUMBER) val number: String?,
    @JsonSchema.Description(ACCOUNT_TERM) @EnumOf(Term::class) val term: String,
)

@Serializable
@JsonSchema.Description(
    "A closed account's transactions dated after its close date. A closed account should have " +
        "none, so they suggest the close date is wrong. See decision 4 in docs/reports.md."
)
data class LateTransactionsResponse(
    @JsonSchema.Description("How many there are.") val count: Int,
    @JsonSchema.Description("The date of the latest.")
    @JsonSchema.Format(DATE_FORMAT)
    val latest: String,
)

@Serializable
@JsonSchema.Description("A closed account. It is left out of the sheet.")
data class ClosedAccountResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(ACCOUNT_NAME) val name: String,
    @JsonSchema.Description(ACCOUNT_NUMBER) val number: String?,
    @JsonSchema.Description(ACCOUNT_TERM) @EnumOf(Term::class) val term: String,
    @JsonSchema.Description("The date the account was closed.")
    @JsonSchema.Format(DATE_FORMAT)
    val closedOn: String,
    // A description here would make Ktor document LateTransactionsResponse twice, so it is on the
    // type.
    val transactionsAfterClose: LateTransactionsResponse?,
)

/** The account's line, or null when its balance is unknown. */
fun AccountBalance.toLine(): AccountLineResponse? = current?.let {
    val (side, magnitude) = BalanceSheet.accountSide(it.balance)
    AccountLineResponse(
        id = account.id,
        name = account.name.value,
        number = account.number?.value,
        side = side.name,
        term = account.term.name,
        balance = magnitude.toString(),
        asOf = it.asOf.formatCalendarDate(),
    )
}

fun Account.toUnknownBalance() = UnknownBalanceResponse(id, name.value, number?.value, term.name)

/** The account's entry, or null while it is open. */
fun Account.toClosed(afterClose: TransactionsAfterClose?): ClosedAccountResponse? = closedOn?.let {
    ClosedAccountResponse(
        id = id,
        name = name.value,
        number = number?.value,
        term = term.name,
        closedOn = it.formatCalendarDate(),
        transactionsAfterClose =
            afterClose?.let { late ->
                LateTransactionsResponse(late.count, late.latest.formatCalendarDate())
            },
    )
}
