package budgeteur.feature.tag

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.withError
import arrow.core.raise.context.zipOrAccumulate
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import io.ktor.openapi.JsonSchema
import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * Payload for creating or replacing a tag. Create generates the id. The fields stay strings, so
 * that [toTag] reports every invalid field rather than the first that fails to decode.
 */
@Serializable
@JsonSchema.Description("Payload for creating or replacing a tag. Create generates the id.")
data class TagRequest(
    @JsonSchema.MinLength(1) @JsonSchema.MaxLength(TagName.MAX_LENGTH) val name: String,
    @JsonSchema.Description(TagDocs.COLOR) @EnumOf(TagColor::class) val color: String,
    @JsonSchema.Description(TagDocs.KIND) @EnumOf(TagKind::class) val kind: String,
)

/**
 * Parses every field, reporting all failures in one error, one per line, so a client sees them
 * together.
 */
context(_: Raise<DomainError>)
fun TagRequest.toTag(id: UUID): Tag =
    withError({ errors: NonEmptyList<String> ->
        DomainError.ValidationFailed(errors.joinToString("\n"))
    }) {
        zipOrAccumulate(
            { TagName.create(name) },
            { TagColor.parse(color) },
            { TagKind.parse(kind) },
        ) { name, color, kind ->
            Tag(id, name, color, kind)
        }
    }
