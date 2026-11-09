package budgeteur.feature.balancesheet

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.BalanceSheetItem
import budgeteur.domain.ItemName
import budgeteur.domain.ItemObservation
import budgeteur.domain.Magnitude
import budgeteur.domain.Money
import budgeteur.domain.Side
import budgeteur.domain.Term
import budgeteur.domain.parseCalendarDate
import budgeteur.domain.requireAsOfDate
import budgeteur.domain.requireCloseDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import io.ktor.openapi.JsonSchema
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.Serializable

// The slice's requests. Fields that hold amounts, dates and enum names stay strings, so the parsers
// report every invalid field rather than the first that fails to decode.

/** Field descriptions the requests and responses share. */
internal object ItemDocs {
    const val NAME = "A human-readable name, e.g. \"House\" or \"Mortgage\"."
    const val SIDE = "Whether the item is an asset or a liability. Fixed at creation."
    const val TERM = "Whether the item is current or non-current."
    const val VALUE =
        "The positive magnitude of the item's value. Direction is implied by the side."
    const val AS_OF = "The date the value is accurate as of."
    const val LATEST = " At most one day after the server's UTC date."
}

/** A value pattern without the sign: a magnitude is never negative. */
internal const val MAGNITUDE_PATTERN = """^\d+(\.\d+)?$"""

@Serializable
@JsonSchema.Description("A value entered by hand, recorded as an observation.")
data class ItemObservationRequest(
    @JsonSchema.Description(ItemDocs.VALUE)
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val value: String,
    @JsonSchema.Description(
        ItemDocs.AS_OF + ItemDocs.LATEST + " Replaces any value on the same date."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
)

@Serializable
@JsonSchema.Description(
    "Payload for creating a balance sheet item with its first value. The id is generated " +
        "server-side."
)
data class CreateBalanceSheetItemRequest(
    @JsonSchema.Description(ItemDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(ItemName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description(ItemDocs.SIDE) @EnumOf(Side::class) val side: String,
    @JsonSchema.Description(ItemDocs.TERM) @EnumOf(Term::class) val term: String,
    @JsonSchema.Description(
        "The positive magnitude of the first value. Direction is implied by side."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val value: String,
    @JsonSchema.Description("The date the first value is accurate as of." + ItemDocs.LATEST)
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
)

@Serializable
@JsonSchema.Description(
    "Payload for updating a balance sheet item's details. Its side is fixed at creation, and its " +
        "values are observations."
)
data class UpdateBalanceSheetItemRequest(
    @JsonSchema.Description(ItemDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(ItemName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description(ItemDocs.TERM) @EnumOf(Term::class) val term: String,
)

@Serializable
@JsonSchema.Description("Payload for closing a balance sheet item: it was sold or repaid.")
data class CloseBalanceSheetItemRequest(
    @JsonSchema.Description(
        "The date the item was sold or repaid." +
            ItemDocs.LATEST +
            " Replaces any earlier close date."
    )
    @JsonSchema.Format(DATE_FORMAT)
    val closedOn: String
)

private fun joined(errors: NonEmptyList<String>) =
    DomainError.ValidationFailed(errors.joinToString("\n"))

context(_: Raise<String>)
private fun magnitude(raw: String): Magnitude = Magnitude.create(Money.parse(raw))

/** An as-of date entered at the instant [now], which bounds it. */
context(_: Raise<String>)
private fun asOfDate(now: Instant, raw: String): LocalDate =
    requireAsOfDate(now, parseCalendarDate(raw))

/** The new item and its first value, reporting every failure, one per line. */
context(_: Raise<DomainError>)
fun CreateBalanceSheetItemRequest.parse(
    id: UUID,
    now: Instant,
): Pair<BalanceSheetItem, ItemObservation> =
    withError(::joined) {
        zipOrAccumulate(
            { ItemName.create(name) },
            { Side.parse(side) },
            { Term.parse(term) },
            { magnitude(value) },
            { asOfDate(now, asOf) },
        ) { name, side, term, value, asOf ->
            BalanceSheetItem(id, name, side, term) to ItemObservation(asOf, value)
        }
    }

/** The item's new details on top of [existing], which keeps its id, side and close date. */
context(_: Raise<DomainError>)
fun UpdateBalanceSheetItemRequest.parse(existing: BalanceSheetItem): BalanceSheetItem =
    withError(::joined) {
        zipOrAccumulate({ ItemName.create(name) }, { Term.parse(term) }) { name, term ->
            existing.copy(name = name, term = term)
        }
    }

/** A value entered at the instant [now], reporting every failure, one per line. */
context(_: Raise<DomainError>)
fun ItemObservationRequest.parse(now: Instant): ItemObservation =
    withError(::joined) {
        zipOrAccumulate({ magnitude(value) }, { asOfDate(now, asOf) }) { value, asOf ->
            ItemObservation(asOf, value)
        }
    }

context(_: Raise<DomainError>)
fun CloseBalanceSheetItemRequest.parse(now: Instant): LocalDate =
    withError(DomainError::ValidationFailed) { requireCloseDate(now, parseCalendarDate(closedOn)) }
