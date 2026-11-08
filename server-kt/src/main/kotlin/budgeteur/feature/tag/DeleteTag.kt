package budgeteur.feature.tag

import arrow.core.raise.ensure
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.Endpoint
import budgeteur.shared.Endpoint.uuidParam
import budgeteur.shared.execute
import budgeteur.shared.log
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import java.sql.Connection
import java.util.UUID

object DeleteTag {
    const val PATH = "/api/tags/{id}"

    /** Returns false when the user has no tag with the id. */
    private fun delete(c: Connection, userId: String, id: UUID): Boolean =
        c.execute("DELETE FROM Tags WHERE Id = ? AND UserId = ?", id, userId) > 0

    fun Route.deleteTag(db: Db) =
        delete(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val id = uuidParam(call, "id")
                ensure(db.run { delete(it, userId, id) }) { DomainError.NotFound("Tag $id not found") }

                call.log.info("Deleted tag $id", "tagId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
}
