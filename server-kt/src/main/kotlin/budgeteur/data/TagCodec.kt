package budgeteur.data

import budgeteur.data.db.tables.records.TagsRecord
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName

fun Tag.toRecord(userId: String) =
    TagsRecord(
        id = id,
        userId = userId,
        name = name.value,
        color = color.name,
        kind = kind.name,
    )

/** The tag endpoints parse every column before writing it, and the database checks kind. */
fun TagsRecord.toTag(): Tag =
    Tag(
        id = id,
        name = TagName.unsafe(name),
        color = TagColor.valueOf(color),
        kind = TagKind.valueOf(kind),
    )
