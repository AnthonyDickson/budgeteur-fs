package budgeteur.feature.transaction

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.TRANSACTIONS
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
import java.util.UUID
import org.jooq.DSLContext

/**
 * The categorisation goes with it, by cascade. Returns false when the user has none with the id.
 */
private fun DSLContext.deleteTransaction(userId: String, id: UUID): Boolean =
    deleteFrom(TRANSACTIONS)
        .where(TRANSACTIONS.ID.eq(id), TRANSACTIONS.USER_ID.eq(userId))
        .execute() > 0

fun Route.deleteTransaction(db: Db) =
    delete("/api/transactions/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { deleteTransaction(userId, id) }) {
                    DomainError.NotFound("Transaction $id not found")
                }

                call.log.info("Deleted transaction $id", "transactionId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete a transaction"
            description = "Permanently removes a transaction. Returns 204 on success."
            tag("Transactions")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
