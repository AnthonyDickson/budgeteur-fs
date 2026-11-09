package budgeteur.feature.transaction

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.requireAccountIfReferenced
import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.data.saveCategorisation
import budgeteur.data.toCategorisation
import budgeteur.domain.Categorisation
import budgeteur.domain.Transaction
import budgeteur.domain.formatCalendarDate
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.put
import java.util.UUID
import org.jooq.DSLContext

/**
 * Replaces the facts but keeps the import hash, which the request does not carry, so a re-import
 * still skips the transaction. Returns false when the user has no transaction with the id.
 */
private fun DSLContext.updateTransaction(userId: String, transaction: Transaction): Boolean =
    update(TRANSACTIONS)
        .set(TRANSACTIONS.AMOUNT, transaction.amount.cents)
        .set(TRANSACTIONS.DESCRIPTION, transaction.description.value)
        .set(TRANSACTIONS.DATE, transaction.date.formatCalendarDate())
        .set(TRANSACTIONS.ACCOUNT_ID, transaction.accountId)
        .where(TRANSACTIONS.ID.eq(transaction.id), TRANSACTIONS.USER_ID.eq(userId))
        .execute() > 0

private fun DSLContext.findCategorisation(userId: String, transactionId: UUID): Categorisation? =
    selectFrom(CATEGORISATIONS)
        .where(
            CATEGORISATIONS.TRANSACTION_ID.eq(transactionId),
            CATEGORISATIONS.USER_ID.eq(userId),
        )
        .fetchOne()
        ?.toCategorisation()

fun Route.updateTransaction(db: Db) =
    put("/api/transactions/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val request = call.receiveOrRaise<TransactionRequest>()
                val transaction = request.toTransaction(id)

                // The current categorisation is read inside the transaction, since keeping the
                // same tag keeps its source.
                val updated = db.transaction {
                    requireAll(
                        { requireTagIfReferenced(userId, request.tagId) },
                        { requireAccountIfReferenced(userId, request.accountId) },
                    )
                    ensure(updateTransaction(userId, transaction)) {
                        DomainError.NotFound("Transaction $id not found")
                    }
                    val categorisation =
                        Categorisation.onUpdate(
                            request.isTransfer,
                            request.tagId,
                            findCategorisation(userId, id),
                        )
                    saveCategorisation(userId, id, categorisation)
                    checkNotNull(findTransaction(userId, id))
                }

                call.log.info("Updated transaction $id", "transactionId" to id)
                call.respond(updated.toResponse())
            }
        }
        .describe {
            summary = "Update a transaction"
            description = "Replaces the transaction."
            tag("Transactions")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<TransactionRequest>()
            }
            responses {
                json<TransactionResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                    HttpStatusCode.Conflict,
                )
            }
        }
