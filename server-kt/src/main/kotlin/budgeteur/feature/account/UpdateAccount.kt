package budgeteur.feature.account

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.requireAll
import budgeteur.domain.Account
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
import org.jooq.DSLContext

/**
 * Replaces the details, leaving the close date and balance history alone. Returns false when the
 * user has no account with the id.
 */
private fun DSLContext.updateAccount(userId: String, account: Account): Boolean =
    update(ACCOUNTS)
        .set(ACCOUNTS.NAME, account.name.value)
        .set(ACCOUNTS.NUMBER, account.number?.value)
        .set(ACCOUNTS.TERM, account.term.name)
        .where(ACCOUNTS.ID.eq(account.id), ACCOUNTS.USER_ID.eq(userId))
        .execute() > 0

fun Route.updateAccount(db: Db) =
    put("/api/accounts/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val account = call.receiveOrRaise<UpdateAccountRequest>().parse(id)

                val updated = db.transaction {
                    requireAll({ requireUniqueNumber(userId, account) })
                    ensure(updateAccount(userId, account)) {
                        DomainError.NotFound("Account $id not found")
                    }
                    checkNotNull(findAccount(userId, id))
                }

                call.log.info("Updated account $id", "accountId" to id)
                call.respond(updated.toResponse())
            }
        }
        .describe {
            summary = "Update an account"
            description =
                "Replaces the account's name, number, and term, leaving its balance history and " +
                    "close date as they are. Returns the account with its current balance."
            tag("Accounts")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<UpdateAccountRequest>()
            }
            responses {
                json<AccountResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                    HttpStatusCode.Conflict,
                )
            }
        }
