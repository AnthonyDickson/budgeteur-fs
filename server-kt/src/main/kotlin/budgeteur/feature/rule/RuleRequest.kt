@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.rule

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

/** Field descriptions the request and response share. */
internal object RuleDocs {
    const val PATTERN =
        "The text to find in transaction descriptions, ignoring case. Unique per user."
    const val TARGET =
        "What the rule proposes when it wins. A tag rule's tag is applied by auto-tagging; a " +
            "transfer rule's transfer is only suggested in quick tagging."
}

@Serializable
@JsonSchema.Description(
    "Payload for creating or replacing a rule. The id is generated server-side."
)
data class RuleRequest(
    @JsonSchema.Description(RuleDocs.PATTERN)
    @JsonSchema.MinLength(1)
    @JsonSchema.MaxLength(RulePattern.MAX_LENGTH)
    val pattern: String,
    @JsonSchema.Description(RuleDocs.TARGET) @EnumOf(RuleTarget.Kind::class) val target: String,
    @JsonSchema.Description("Required for a tag rule, and rejected for a transfer rule.")
    @JsonSchema.Format("uuid")
    val tagId: UUID? = null,
)

/** The rule with [id], reporting every failure, one per line. */
context(_: Raise<DomainError>)
fun RuleRequest.toRule(id: UUID): Rule =
    withError({ errors: NonEmptyList<String> ->
        DomainError.ValidationFailed(errors.joinToString("\n"))
    }) {
        zipOrAccumulate({ RulePattern.create(pattern) }, { RuleTarget.create(target, tagId) }) {
            pattern,
            target ->
            Rule(id, pattern, target)
        }
    }
