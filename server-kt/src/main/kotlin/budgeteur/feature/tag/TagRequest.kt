package budgeteur.feature.tag

import arrow.core.raise.Raise
import arrow.core.raise.withError
import arrow.core.raise.zipOrAccumulate
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName
import budgeteur.shared.DomainError
import java.util.UUID
import kotlinx.serialization.Serializable

/** Payload for creating or replacing a tag. Create generates the id. */
@Serializable
data class TagRequest(
    val name: String,
    /** A Catppuccin accent colour, by name. */
    val color: String,
    /** Which side of the income statement the tag's transactions are on. */
    val kind: String,
)

/**
 * Parses every field, reporting all failures in one error, one per line, so a
 * client sees them together.
 */
fun Raise<DomainError>.parseTag(id: UUID, request: TagRequest): Tag =
    withError({ errors -> DomainError.ValidationFailed(errors.joinToString("\n")) }) {
        zipOrAccumulate(
            { TagName.create(request.name).bind() },
            { TagColor.parse(request.color).bind() },
            { TagKind.parse(request.kind).bind() },
        ) { name, color, kind -> Tag(id, name, color, kind) }
    }
