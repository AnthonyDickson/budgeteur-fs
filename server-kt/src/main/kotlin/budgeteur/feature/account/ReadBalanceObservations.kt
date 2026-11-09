package budgeteur.feature.account

import arrow.core.raise.context.ensureNotNull
import budgeteur.data.db.tables.references.BALANCE_OBSERVATIONS
import budgeteur.data.toObservation
import budgeteur.domain.BalanceObservation
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
import java.util.UUID
import org.jooq.DSLContext

/** The account's observations, newest first, or null when the user has no account with the id. */
private fun DSLContext.readObservations(
    userId: String,
    accountId: UUID,
): List<BalanceObservation>? =
    if (!accountExists(userId, accountId)) {
        null
    } else {
        selectFrom(BALANCE_OBSERVATIONS)
            .where(
                BALANCE_OBSERVATIONS.ACCOUNT_ID.eq(accountId),
                BALANCE_OBSERVATIONS.USER_ID.eq(userId),
            )
            .orderBy(BALANCE_OBSERVATIONS.AS_OF.desc())
            .fetch { it.toObservation() }
    }

fun Route.readBalanceObservations(db: Db) =
    get("/api/accounts/{id}/observations") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val observations =
                    ensureNotNull(db.sql { readObservations(userId, id) }) {
                        DomainError.NotFound("Account $id not found")
                    }

                call.log.info(
                    "Returned ${observations.size} balances for account $id",
                    "accountId" to id,
                )
                call.respond(observations.map { it.toResponse() })
            }
        }
        .describe {
            summary = "List an account's balances"
            description =
                "Returns every balance recorded for the account, newest first. The first is the " +
                    "current balance."
            tag("Accounts")
            uuidPath("id")
            responses {
                json<List<AccountBalanceResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
