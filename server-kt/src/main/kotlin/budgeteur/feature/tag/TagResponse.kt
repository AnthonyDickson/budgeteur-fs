package budgeteur.feature.tag

import budgeteur.domain.Tag
import budgeteur.shared.UuidSerializer
import java.util.UUID
import kotlinx.serialization.Serializable

@Serializable
data class TagResponse(
    @Serializable(with = UuidSerializer::class) val id: UUID,
    val name: String,
    /** A Catppuccin accent colour, by name. */
    val color: String,
    /** Which side of the income statement the tag's transactions are on. */
    val kind: String,
)

fun Tag.toResponse() = TagResponse(id, name.value, color.name, kind.name)
