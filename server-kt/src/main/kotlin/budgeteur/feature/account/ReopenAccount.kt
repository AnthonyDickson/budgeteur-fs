package budgeteur.feature.account

import arrow.core.raise.context.ensure
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

fun Route.reopenAccount(db: Db) =
    delete("/api/accounts/{id}/close-date") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { setCloseDate(userId, id, null) }) {
                    DomainError.NotFound("Account $id not found")
                }

                call.log.info("Reopened account $id", "accountId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Reopen an account"
            description =
                "Clears the account's close date, so every balance sheet includes it again. " +
                    "Returns 204 on success, including for an account that is already open."
            tag("Accounts")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
