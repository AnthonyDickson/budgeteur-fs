package budgeteur.feature.account

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

fun Route.readAccount(db: Db) =
    get("/api/accounts/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val account =
                    ensureNotNull(db.sql { findAccount(userId, id) }) {
                        DomainError.NotFound("Account $id not found")
                    }

                call.log.info("Returned account $id", "accountId" to id)
                call.respond(account.toResponse())
            }
        }
        .describe {
            summary = "Get an account by ID"
            description = "Returns the account with its current balance, or 404 if not found."
            tag("Accounts")
            uuidPath("id")
            responses {
                json<AccountResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
