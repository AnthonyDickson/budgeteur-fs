package budgeteur.feature.tag

import arrow.core.raise.context.ensureNotNull
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.toTag
import budgeteur.domain.Tag
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import java.util.UUID
import org.jooq.DSLContext

private fun DSLContext.findTag(userId: String, id: UUID): Tag? =
    selectFrom(TAGS).where(TAGS.ID.eq(id), TAGS.USER_ID.eq(userId)).fetchOne()?.toTag()

fun Route.readTag(db: Db) =
    get("/api/tags/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val tag =
                    ensureNotNull(db.sql { findTag(userId, id) }) {
                        DomainError.NotFound("Tag $id not found")
                    }

                call.log.info("Returned tag $id", "tagId" to id)
                call.respond(tag.toResponse())
            }
        }
        .describe {
            summary = "Get a tag by ID"
            description = "Returns a single tag, or 404 if not found."
            tag("Tags")
            uuidPath("id")
            responses {
                json<TagResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
