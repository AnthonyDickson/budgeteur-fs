package budgeteur.feature.balancesheet

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

fun Route.readAllBalanceSheetItems(db: Db) =
    get("/api/balance-sheet/items") {
            call.handle {
                val userId = call.userId
                val items = db.sql { readAllItems(userId) }

                call.log.info("Returned ${items.size} balance sheet items", "count" to items.size)
                call.respond(items.map { it.toResponse() })
            }
        }
        .describe {
            summary = "Get all balance sheet items"
            description = "Development only. Returns every balance sheet item of the user."
            tag("Balance Sheets")
            responses {
                json<List<BalanceSheetItemResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
