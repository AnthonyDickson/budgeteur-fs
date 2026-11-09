package budgeteur.feature.account

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.ACCOUNTS
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
 * The balance history and transactions go with it, by cascade. Returns false when the user has no
 * account with the id.
 */
private fun DSLContext.deleteAccount(userId: String, id: UUID): Boolean =
    deleteFrom(ACCOUNTS).where(ACCOUNTS.ID.eq(id), ACCOUNTS.USER_ID.eq(userId)).execute() > 0

fun Route.deleteAccount(db: Db) =
    delete("/api/accounts/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { deleteAccount(userId, id) }) {
                    DomainError.NotFound("Account $id not found")
                }

                call.log.info("Deleted account $id", "accountId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete an account"
            description =
                "Permanently removes an account with its balance history and its transactions. " +
                    "Returns 204 on success."
            tag("Accounts")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
