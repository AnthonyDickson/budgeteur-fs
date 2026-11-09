@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.transaction

import budgeteur.domain.Categorisation
import budgeteur.domain.Source
import budgeteur.domain.formatCalendarDate
import budgeteur.domain.isTransfer
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/** Field descriptions the request and response share. */
internal object TransactionDocs {
    const val AMOUNT = "A debit (negative) or credit (positive), as a decimal string."
    const val DATE = "The calendar day the transaction occurred."
    const val IS_TRANSFER =
        "Whether the transaction moves money between the user's own accounts. A transfer is " +
            "neither income nor expense."
}

@Serializable
@JsonSchema.Description("A transaction's tag and who decided it.")
data class TransactionTagResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(
        "Who decided the tag: the user without a suggestion (Manual) or by choosing one " +
            "(Accepted), or a rule (Rule). Re-tag recomputes only rule tags. Detected is reserved " +
            "for transfers, which have no tag."
    )
    @EnumOf(Source::class)
    val source: String,
)

@Serializable
data class TransactionResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(TransactionDocs.AMOUNT)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val amount: String,
    val description: String,
    @JsonSchema.Description(TransactionDocs.DATE) @JsonSchema.Format(DATE_FORMAT) val date: String,
    @JsonSchema.Description(TransactionDocs.IS_TRANSFER) val isTransfer: Boolean,
    @JsonSchema.Format("uuid") val accountId: UUID?,
    @JsonSchema.Description("The name of the transaction's account, if it has one.")
    val accountName: String?,
    @JsonSchema.Description(
        "The transaction's tag, or none when it is untagged, dismissed, or a transfer."
    )
    val tag: TransactionTagResponse?,
)

fun TransactionDetails.toResponse(): TransactionResponse {
    val tag = categorisation as? Categorisation.Tagged
    return TransactionResponse(
        id = transaction.id,
        amount = transaction.amount.toString(),
        description = transaction.description.value,
        date = transaction.date.formatCalendarDate(),
        isTransfer = categorisation.isTransfer,
        accountId = transaction.accountId,
        accountName = accountName,
        tag = tag?.let { TransactionTagResponse(it.tagId, it.source.name) },
    )
}
