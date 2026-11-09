package budgeteur.feature.account

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.Account
import budgeteur.domain.AccountName
import budgeteur.domain.AccountNumber
import budgeteur.domain.BalanceObservation
import budgeteur.domain.Money
import budgeteur.domain.Term
import budgeteur.domain.parseCalendarDate
import budgeteur.domain.requireCloseDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import io.ktor.openapi.JsonSchema
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

// The slice's requests. Fields that hold amounts, dates and enum names stay strings, so the parsers
// report every invalid field rather than the first that fails to decode.

/** Field descriptions the requests and responses share. */
internal object AccountDocs {
    const val NAME = "The user's alias for the account."
    const val NUMBER =
        "The number statements identify the account by: an NZ bank account number, stored in " +
            "canonical form, or a masked card number."
    const val TERM = "Whether the account is current or non-current."
    const val BALANCE = "Signed: positive is an asset (owned), negative a liability (owed)."
    const val AS_OF = "The date the balance is accurate as of."
}

@Serializable
@JsonSchema.Description(
    "A balance entered by hand, recorded as an observation. Optional on create, as the opening " +
        "balance; without one the balance is unknown."
)
data class BalanceEntryRequest(
    @JsonSchema.Description(AccountDocs.BALANCE)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val balance: String,
    @JsonSchema.Description(
        AccountDocs.AS_OF +
            " At most one day after the server's UTC date. Replaces any balance on the same date."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
)

@Serializable
@JsonSchema.Description("Payload for creating an account. The id is generated server-side.")
data class CreateAccountRequest(
    @JsonSchema.Description(AccountDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(AccountName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description("${AccountDocs.NUMBER} None, or blank, for an account without one.")
    val number: String? = null,
    @JsonSchema.Description(AccountDocs.TERM) @EnumOf(Term::class) val term: String,
    // A description here would make Ktor document BalanceEntryRequest twice, so it is on the type.
    val balance: BalanceEntryRequest? = null,
)

@Serializable
@JsonSchema.Description("Payload for updating an account's details. Balances are recorded apart.")
data class UpdateAccountRequest(
    @JsonSchema.Description(AccountDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(AccountName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description("${AccountDocs.NUMBER} None, or blank, for an account without one.")
    val number: String? = null,
    @JsonSchema.Description(AccountDocs.TERM) @EnumOf(Term::class) val term: String,
)

@Serializable
@JsonSchema.Description("Payload for closing an account.")
data class CloseAccountRequest(
    @JsonSchema.Description(
        "The date the account was closed. At most one day after the server's UTC date. " +
            "Replaces any earlier close date."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val closedOn: String
)

private fun joined(errors: NonEmptyList<String>) =
    DomainError.ValidationFailed(errors.joinToString("\n"))

/** Blank is none. */
context(_: Raise<String>)
private fun parseNumber(raw: String?): AccountNumber? =
    if (raw.isNullOrBlank()) null else AccountNumber.create(raw)

/** A balance entered at the instant [now], which bounds its as-of date. */
context(_: Raise<String>)
private fun BalanceEntryRequest.toObservation(now: Instant): BalanceObservation =
    BalanceObservation.create(now, parseCalendarDate(asOf), Money.parse(balance))

/** The new account and its opening balance, if any, reporting every failure, one per line. */
context(_: Raise<DomainError>)
fun CreateAccountRequest.parse(id: UUID, now: Instant): Pair<Account, BalanceObservation?> =
    withError(::joined) {
        zipOrAccumulate(
            { AccountName.create(name) },
            { parseNumber(number) },
            { Term.parse(term) },
            { balance?.toObservation(now) },
        ) { name, number, term, balance ->
            Account(id, number, name, term) to balance
        }
    }

/** The account's new details, reporting every failure, one per line. */
context(_: Raise<DomainError>)
fun UpdateAccountRequest.parse(id: UUID): Account =
    withError(::joined) {
        zipOrAccumulate(
            { AccountName.create(name) },
            { parseNumber(number) },
            { Term.parse(term) },
        ) { name, number, term ->
            Account(id, number, name, term)
        }
    }

context(_: Raise<DomainError>)
fun BalanceEntryRequest.parse(now: Instant): BalanceObservation =
    withError(DomainError::ValidationFailed) { toObservation(now) }

context(_: Raise<DomainError>)
fun CloseAccountRequest.parse(now: Instant): LocalDate =
    withError(DomainError::ValidationFailed) { requireCloseDate(now, parseCalendarDate(closedOn)) }
