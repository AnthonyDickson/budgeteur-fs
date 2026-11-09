package budgeteur.feature.transaction

import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.requireAccountIfReferenced
import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.data.saveCategorisation
import budgeteur.data.toRecord
import budgeteur.domain.Categorisation
import budgeteur.shared.Db
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.newId
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.post

fun Route.createTransaction(db: Db) =
    post("/api/transactions") {
            call.handle {
                val userId = call.userId
                val request = call.receiveOrRaise<TransactionRequest>()
                val transaction = request.toTransaction(newId())

                val created = db.transaction {
                    requireAll(
                        { requireTagIfReferenced(userId, request.tagId) },
                        { requireAccountIfReferenced(userId, request.accountId) },
                    )
                    insertInto(TRANSACTIONS).set(transaction.toRecord(userId)).execute()
                    saveCategorisation(
                        userId,
                        transaction.id,
                        Categorisation.onCreate(request.isTransfer, request.tagId),
                    )
                    checkNotNull(findTransaction(userId, transaction.id))
                }

                call.log.info(
                    "Created transaction ${transaction.id}",
                    "transactionId" to transaction.id,
                )
                call.respond(HttpStatusCode.Created, created.toResponse())
            }
        }
        .describe {
            summary = "Create a transaction"
            description = "Creates a new transaction and returns it with status 201."
            tag("Transactions")
            requestBody {
                required = true
                schema = jsonSchema<TransactionRequest>()
            }
            responses {
                json<TransactionResponse>(HttpStatusCode.Created)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.Conflict,
                )
            }
        }
