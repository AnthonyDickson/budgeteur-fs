package budgeteur.feature.tag

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.TAGS
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.noContent
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.openapi.describe
import java.util.UUID
import org.jooq.DSLContext

/** Returns false when the user has no tag with the id. */
private fun DSLContext.deleteTag(userId: String, id: UUID): Boolean =
    deleteFrom(TAGS).where(TAGS.ID.eq(id), TAGS.USER_ID.eq(userId)).execute() > 0

fun Route.deleteTag(db: Db) =
    delete("/api/tags/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { deleteTag(userId, id) }) {
                    DomainError.NotFound("Tag $id not found")
                }

                call.log.info("Deleted tag $id", "tagId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete a tag"
            description = "Permanently removes a tag. Returns 204 on success."
            tag("Tags")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
