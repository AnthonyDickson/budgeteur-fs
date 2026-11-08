package budgeteur.data

import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName
import budgeteur.shared.uuid
import java.sql.ResultSet

object TagCodec {
    const val COLUMNS = "Id, Name, Color, Kind"

    /** Reads a row selected with [COLUMNS]. The tag endpoints parse every column before writing it. */
    fun fromRow(rs: ResultSet): Tag =
        Tag(
            id = rs.uuid("Id"),
            name = TagName.unsafe(rs.getString("Name")),
            color = TagColor.valueOf(rs.getString("Color")),
            kind = TagKind.valueOf(rs.getString("Kind")),
        )
}
