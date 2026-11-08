package budgeteur.feature.tag

import arrow.core.Either
import arrow.core.raise.ensure
import arrow.core.raise.either
import budgeteur.data.ConstraintError
import budgeteur.data.Constraints.requireAll
import budgeteur.domain.Tag
import budgeteur.domain.TagName
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.Endpoint
import budgeteur.shared.Json
import budgeteur.shared.count
import budgeteur.shared.execute
import budgeteur.shared.log
import budgeteur.shared.uuidV7
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import java.sql.Connection

object CreateTag {
    const val PATH = "/api/tags"

    /** The `UNIQUE(UserId, Name)` constraint. */
    private fun requireNameIsUnique(c: Connection, userId: String, name: TagName): Either<ConstraintError, Unit> =
        either {
            val rows = c.count("SELECT COUNT(*) FROM Tags WHERE UserId = ? AND Name = ?", userId, name.value)
            ensure(rows == 0) { ConstraintError("A tag with the name '${name.value}' already exists") }
        }

    private fun insert(c: Connection, userId: String, tag: Tag) {
        c.execute(
            "INSERT INTO Tags (Id, UserId, Name, Color, Kind) VALUES (?, ?, ?, ?, ?)",
            tag.id, userId, tag.name.value, tag.color.name, tag.kind.name,
        )
    }

    fun Route.createTag(db: Db) =
        post(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val request = Json.read<TagRequest>(call).bind()
                val tag = parseTag(uuidV7(), request)

                requireAll(db.run { requireNameIsUnique(it, userId, tag.name) })
                db.run { insert(it, userId, tag) }

                call.log.info("Created tag ${tag.id}", "tagId" to tag.id)
                Json.write(call, TagResponse.fromDomain(tag), HttpStatusCode.Created)
            }
        }
}
