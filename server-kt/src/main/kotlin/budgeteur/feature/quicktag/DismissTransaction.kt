package budgeteur.feature.quicktag

import budgeteur.domain.Categorisation
import budgeteur.shared.Db
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

fun Route.dismissTransaction(db: Db) =
    delete("/api/quick-tag/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")

                db.transaction { saveChoice(userId, id, Categorisation.Dismissed) }

                call.log.info("Dismissed transaction $id", "transactionId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Dismiss a transaction"
            description =
                "Records that the transaction has no tag, which removes it from the quick " +
                    "tagging queue. Rules never tag a dismissed transaction. Returns 204 on success."
            tag("Quick tagging")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
