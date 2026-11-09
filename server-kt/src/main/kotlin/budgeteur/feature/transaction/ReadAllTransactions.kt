package budgeteur.feature.transaction

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

/**
 * Every transaction of the user, for manual testing and inspection. Development only: the page
 * reads through search. See decision 7 in docs/transaction-search.md.
 */
fun Route.readAllTransactions(db: Db) =
    get("/api/transactions") {
            call.handle {
                val transactions = db.sql { readAllTransactions(call.userId) }

                call.log.info(
                    "Returned ${transactions.size} transactions",
                    "count" to transactions.size,
                )
                call.respond(transactions.map { it.toResponse() })
            }
        }
        .describe {
            summary = "Get all transactions"
            description = "Development only. Returns every transaction of the user."
            tag("Transactions")
            responses {
                json<List<TransactionResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
