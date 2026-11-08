package budgeteur.feature.testsupport

import budgeteur.data.db.tables.references.TAGS
import budgeteur.shared.Db
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.openapi.hide

/**
 * Deletes all of the current user's data, so each E2E test starts empty. Registered in Development
 * only, so it can never be reached against real data.
 */
fun Route.resetUserData(db: Db) =
    delete("/api/test/user-data") {
            call.handle {
                val userId = call.userId
                val tags = db.transaction {
                    deleteFrom(TAGS).where(TAGS.USER_ID.eq(userId)).execute()
                }

                call.log.info("Reset user data", "tagsDeleted" to tags)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .hide()
