package budgeteur.feature.balancesheet

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

fun Route.reopenBalanceSheetItem(db: Db) =
    delete("/api/balance-sheet/items/{id}/close-date") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { setCloseDate(userId, id, null) }) {
                    DomainError.NotFound("Balance sheet item $id not found")
                }

                call.log.info("Reopened balance sheet item $id", "balanceSheetItemId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Reopen a balance sheet item"
            description =
                "Clears the item's close date, so every balance sheet includes it again. Returns " +
                    "204 on success, including for an item that is already open."
            tag("Balance Sheets")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
