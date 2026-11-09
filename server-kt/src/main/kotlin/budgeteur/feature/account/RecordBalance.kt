package budgeteur.feature.account

import arrow.core.raise.context.ensure
import budgeteur.data.recordBalance
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
import io.ktor.server.routing.post
import java.time.Instant

fun Route.recordBalance(db: Db, clock: () -> Instant) =
    post("/api/accounts/{id}/observations") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val observation = call.receiveOrRaise<BalanceEntryRequest>().parse(clock())

                val account = db.transaction {
                    ensure(accountExists(userId, id)) {
                        DomainError.NotFound("Account $id not found")
                    }
                    recordBalance(userId, id, observation)
                    checkNotNull(findAccount(userId, id))
                }

                call.log.info("Recorded a balance for account $id", "accountId" to id)
                call.respond(account.toResponse())
            }
        }
        .describe {
            summary = "Record an account's balance"
            description =
                "Records the account's balance as of a date, replacing any balance on that date. " +
                    "Returns the account with its current balance: the latest by as-of date, so " +
                    "an older balance does not replace a newer one."
            tag("Accounts")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<BalanceEntryRequest>()
            }
            responses {
                json<AccountResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
