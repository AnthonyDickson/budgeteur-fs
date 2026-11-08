package budgeteur.data

import budgeteur.data.db.tables.records.TagsRecord
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName

object TagCodec {
    fun toRow(tag: Tag, userId: String) =
        TagsRecord(
            id = tag.id,
            userId = userId,
            name = tag.name.value,
            color = tag.color.name,
            kind = tag.kind.name,
        )

    /** The tag endpoints parse every column before writing it, and the database checks kind. */
    fun fromRow(row: TagsRecord): Tag =
        Tag(
            id = row.id,
            name = TagName.unsafe(row.name),
            color = TagColor.valueOf(row.color),
            kind = TagKind.valueOf(row.kind),
        )
}
