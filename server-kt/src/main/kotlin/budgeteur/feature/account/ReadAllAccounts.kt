package budgeteur.feature.account

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

fun Route.readAllAccounts(db: Db) =
    get("/api/accounts") {
            call.handle {
                val accounts = db.sql { readAllAccounts(call.userId) }

                call.log.info("Returned ${accounts.size} accounts", "count" to accounts.size)
                call.respond(accounts.map { it.toResponse() })
            }
        }
        .describe {
            summary = "Get all accounts"
            description = "Returns the user's accounts with their current balances, by name."
            tag("Accounts")
            responses {
                json<List<AccountResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
