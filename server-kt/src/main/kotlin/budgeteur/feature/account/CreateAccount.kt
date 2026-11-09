package budgeteur.feature.account

import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.recordBalance
import budgeteur.data.requireAll
import budgeteur.data.toRecord
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
import java.time.Instant

fun Route.createAccount(db: Db, clock: () -> Instant) =
    post("/api/accounts") {
            call.handle {
                val userId = call.userId
                val (account, opening) =
                    call.receiveOrRaise<CreateAccountRequest>().parse(newId(), clock())

                val created = db.transaction {
                    requireAll({ requireUniqueNumber(userId, account) })
                    insertInto(ACCOUNTS).set(account.toRecord(userId)).execute()
                    opening?.let { recordBalance(userId, account.id, it) }
                    checkNotNull(findAccount(userId, account.id))
                }

                call.log.info("Created account ${account.id}", "accountId" to account.id)
                call.respond(HttpStatusCode.Created, created.toResponse())
            }
        }
        .describe {
            summary = "Create an account"
            description =
                "Creates an account, recording its balance when one is given, and returns it " +
                    "with status 201."
            tag("Accounts")
            requestBody {
                required = true
                schema = jsonSchema<CreateAccountRequest>()
            }
            responses {
                json<AccountResponse>(HttpStatusCode.Created)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.Conflict,
                )
            }
        }
