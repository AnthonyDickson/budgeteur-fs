package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensureNotNull
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

fun Route.readBalanceSheetItem(db: Db) =
    get("/api/balance-sheet/items/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val item =
                    ensureNotNull(db.sql { findItem(userId, id) }) {
                        DomainError.NotFound("Balance sheet item $id not found")
                    }

                call.log.info("Returned balance sheet item $id", "balanceSheetItemId" to id)
                call.respond(item.toResponse())
            }
        }
        .describe {
            summary = "Get a balance sheet item"
            description = "Returns the item with its current value, or 404 if not found."
            tag("Balance Sheets")
            uuidPath("id")
            responses {
                json<BalanceSheetItemResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
