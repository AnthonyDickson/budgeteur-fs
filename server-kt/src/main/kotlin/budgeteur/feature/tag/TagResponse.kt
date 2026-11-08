package budgeteur.feature.tag

import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable

/** Field descriptions the request and response share. */
internal object TagDocs {
    const val COLOR = "A Catppuccin accent colour, by name."
    const val KIND = "Which side of the income statement the tag's transactions are on."
}

@Serializable
data class TagResponse(
    @Serializable(with = UuidSerializer::class) @JsonSchema.Format("uuid") val id: UUID,
    val name: String,
    @JsonSchema.Description(TagDocs.COLOR) @EnumOf(TagColor::class) val color: String,
    @JsonSchema.Description(TagDocs.KIND) @EnumOf(TagKind::class) val kind: String,
)

fun Tag.toResponse() = TagResponse(id, name.value, color.name, kind.name)
