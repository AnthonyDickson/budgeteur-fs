package budgeteur.feature.tag

import arrow.core.Either
import arrow.core.raise.either
import arrow.core.raise.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.Constraints.requireAll
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.Endpoint
import budgeteur.shared.Endpoint.uuidParam
import budgeteur.shared.Json
import budgeteur.shared.count
import budgeteur.shared.execute
import budgeteur.shared.log
import io.ktor.server.routing.Route
import io.ktor.server.routing.put
import java.sql.Connection

object UpdateTag {
    const val PATH = "/api/tags/{id}"

    /** The `UNIQUE(UserId, Name)` constraint, ignoring the tag being updated. */
    private fun requireNameIsUnique(c: Connection, userId: String, tag: Tag): Either<ConstraintError, Unit> =
        either {
            val rows =
                c.count(
                    "SELECT COUNT(*) FROM Tags WHERE UserId = ? AND Name = ? AND Id <> ?",
                    userId, tag.name.value, tag.id,
                )
            ensure(rows == 0) { ConstraintError("A tag with the name '${tag.name.value}' already exists") }
        }

    /** Returns false when the user has no tag with the id. */
    private fun update(c: Connection, userId: String, tag: Tag): Boolean =
        c.execute(
            "UPDATE Tags SET Name = ?, Color = ?, Kind = ? WHERE Id = ? AND UserId = ?",
            tag.name.value, tag.color.name, tag.kind.name, tag.id, userId,
        ) > 0

    fun Route.updateTag(db: Db) =
        put(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val id = uuidParam(call, "id")
                val request = Json.read<TagRequest>(call).bind()
                val tag = parseTag(id, request)

                requireAll(db.run { requireNameIsUnique(it, userId, tag) })
                ensure(db.run { update(it, userId, tag) }) { DomainError.NotFound("Tag $id not found") }

                call.log.info("Updated tag $id", "tagId" to id)
                Json.write(call, TagResponse.fromDomain(tag))
            }
        }
}
