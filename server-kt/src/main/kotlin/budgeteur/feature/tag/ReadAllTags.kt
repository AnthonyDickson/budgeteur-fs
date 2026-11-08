package budgeteur.feature.tag

import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.toTag
import budgeteur.domain.Tag
import budgeteur.shared.Db
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import org.jooq.DSLContext

private fun DSLContext.findTags(userId: String): List<Tag> =
    selectFrom(TAGS).where(TAGS.USER_ID.eq(userId)).fetch { it.toTag() }

fun Route.readAllTags(db: Db) =
    get("/api/tags") {
            call.handle {
                val userId = call.userId
                val tags = db.sql { findTags(userId) }

                call.log.info("Returned ${tags.size} tags", "count" to tags.size)
                call.respond(tags.map { it.toResponse() })
            }
        }
        .describe {
            summary = "List all tags"
            description = "Returns all of the user's tags."
            tag("Tags")
            responses {
                json<List<TagResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
