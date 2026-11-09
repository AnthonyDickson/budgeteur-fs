@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.account

import budgeteur.domain.AccountName
import budgeteur.domain.BalanceObservation
import budgeteur.domain.Term
import budgeteur.domain.formatCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description(
    "A balance an account had as of a date. An account's current balance is the latest by " +
        "as-of date; none when its balance is unknown."
)
data class AccountBalanceResponse(
    @JsonSchema.Description(AccountDocs.BALANCE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val balance: String,
    @JsonSchema.Description(AccountDocs.AS_OF) @JsonSchema.Format(DATE_FORMAT) val asOf: String,
)

@Serializable
@JsonSchema.Description("A closed account's transactions after its close date.")
data class TransactionsAfterCloseResponse(
    @JsonSchema.Description("How many there are.") val count: Int,
    @JsonSchema.Description("The date of the latest.")
    @JsonSchema.Format(DATE_FORMAT)
    val latest: String,
)

@Serializable
data class AccountResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(AccountDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(AccountName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description("${AccountDocs.NUMBER} None for an account without one.")
    val number: String?,
    @JsonSchema.Description(AccountDocs.TERM) @EnumOf(Term::class) val term: String,
    // A description here would make Ktor document AccountBalanceResponse twice, so it is on the
    // type.
    val balance: AccountBalanceResponse?,
    @JsonSchema.Description("The date the account was closed, or none while it is open.")
    @JsonSchema.Format(DATE_FORMAT)
    val closedOn: String?,
    @JsonSchema.Description(
        "Transactions dated after the close date, or none. A closed account should have none, " +
            "so they suggest the close date is wrong."
    )
    val transactionsAfterClose: TransactionsAfterCloseResponse?,
)

fun BalanceObservation.toResponse() =
    AccountBalanceResponse(balance.toString(), asOf.formatCalendarDate())

fun AccountDetails.toResponse(): AccountResponse {
    val account = balance.account
    return AccountResponse(
        id = account.id,
        name = account.name.value,
        number = account.number?.value,
        term = account.term.name,
        balance = balance.current?.toResponse(),
        closedOn = account.closedOn?.formatCalendarDate(),
        transactionsAfterClose =
            transactionsAfterClose?.let {
                TransactionsAfterCloseResponse(it.count, it.latest.formatCalendarDate())
            },
    )
}
