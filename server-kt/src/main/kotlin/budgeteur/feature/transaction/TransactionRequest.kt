@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.transaction

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.Categorisation
import budgeteur.domain.Money
import budgeteur.domain.Transaction
import budgeteur.domain.TransactionDescription
import budgeteur.domain.parseCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.DomainError
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/**
 * Payload for creating or replacing a transaction. Create generates the id. The amount and date
 * stay strings, so that [toTransaction] reports every invalid field rather than the first that
 * fails to decode.
 */
@Serializable
@JsonSchema.Description(
    "Payload for creating or replacing a transaction. Create generates the id. A transfer has no tag."
)
data class TransactionRequest(
    @JsonSchema.Description(TransactionDocs.AMOUNT)
    @JsonSchema.Pattern(MONEY_PATTERN)
    val amount: String,
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(TransactionDescription.MAX_LENGTH)
    val description: String,
    @JsonSchema.Description(TransactionDocs.DATE) @JsonSchema.Format(DATE_FORMAT) val date: String,
    @JsonSchema.Description(TransactionDocs.IS_TRANSFER) val isTransfer: Boolean,
    @JsonSchema.Format("uuid") val tagId: UUID? = null,
    @JsonSchema.Format("uuid") val accountId: UUID? = null,
)

/** Parses every field, reporting all failures in one error, one per line. */
context(_: Raise<DomainError>)
fun TransactionRequest.toTransaction(id: UUID): Transaction =
    withError({ errors: NonEmptyList<String> ->
        DomainError.ValidationFailed(errors.joinToString("\n"))
    }) {
        zipOrAccumulate(
            { Money.parse(amount) },
            { TransactionDescription.create(description) },
            { parseCalendarDate(date) },
            { Categorisation.requireNoTagOnTransfer(isTransfer, tagId) },
        ) { amount, description, date, _ ->
            Transaction(id, amount, description, date, accountId)
        }
    }
