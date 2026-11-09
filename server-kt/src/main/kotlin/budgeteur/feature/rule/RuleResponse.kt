@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.rule

import budgeteur.domain.Rule
import budgeteur.domain.RuleTarget
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
data class RuleResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description(RuleDocs.PATTERN) val pattern: String,
    @JsonSchema.Description(RuleDocs.TARGET) @EnumOf(RuleTarget.Kind::class) val target: String,
    @JsonSchema.Description("The tag a tag rule proposes. None for a transfer rule.")
    @JsonSchema.Format("uuid")
    val tagId: UUID?,
)

fun Rule.toResponse() = RuleResponse(id, pattern.value, target.kind.name, target.tagId)
