@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.balancesheet

import budgeteur.domain.ItemName
import budgeteur.domain.ItemObservation
import budgeteur.domain.ItemValue
import budgeteur.domain.Side
import budgeteur.domain.Term
import budgeteur.domain.formatCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description("A balance sheet item with its current value.")
data class BalanceSheetItemResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(ItemDocs.NAME)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(ItemName.MAX_LENGTH)
    val name: String,
    @JsonSchema.Description(ItemDocs.SIDE) @EnumOf(Side::class) val side: String,
    @JsonSchema.Description(ItemDocs.TERM) @EnumOf(Term::class) val term: String,
    @JsonSchema.Description(
        "The positive magnitude of the item's current value: its latest observation. " +
            "Direction is implied by the side."
    )
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val value: String,
    @JsonSchema.Description("The date the current value is accurate as of.")
    @JsonSchema.Format(DATE_FORMAT)
    val asOf: String,
    @JsonSchema.Description("The date the item was sold or repaid, or none while it is held.")
    @JsonSchema.Format(DATE_FORMAT)
    val closedOn: String?,
)

@Serializable
@JsonSchema.Description("A value recorded for an item.")
data class ItemObservationResponse(
    @JsonSchema.Description(ItemDocs.VALUE)
    @JsonSchema.Pattern(MAGNITUDE_PATTERN)
    val value: String,
    @JsonSchema.Description(ItemDocs.AS_OF) @JsonSchema.Format(DATE_FORMAT) val asOf: String,
)

fun ItemObservation.toResponse() =
    ItemObservationResponse(value.amount.toString(), asOf.formatCalendarDate())

fun ItemValue.toResponse() =
    BalanceSheetItemResponse(
        id = item.id,
        name = item.name.value,
        side = item.side.name,
        term = item.term.name,
        value = current.value.amount.toString(),
        asOf = current.asOf.formatCalendarDate(),
        closedOn = item.closedOn?.formatCalendarDate(),
    )
