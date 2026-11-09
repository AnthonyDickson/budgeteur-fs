package budgeteur.feature.transaction

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

fun Route.readTransaction(db: Db) =
    get("/api/transactions/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val details =
                    ensureNotNull(db.sql { findTransaction(userId, id) }) {
                        DomainError.NotFound("Transaction $id not found")
                    }

                call.log.info("Returned transaction $id", "transactionId" to id)
                call.respond(details.toResponse())
            }
        }
        .describe {
            summary = "Get a transaction by ID"
            description = "Returns a single transaction, or 404 if not found."
            tag("Transactions")
            uuidPath("id")
            responses {
                json<TransactionResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
