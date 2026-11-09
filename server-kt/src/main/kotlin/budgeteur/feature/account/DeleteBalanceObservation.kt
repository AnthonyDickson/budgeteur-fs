package budgeteur.feature.account

import arrow.core.raise.context.ensure
import arrow.core.raise.context.withError
import budgeteur.data.db.tables.references.BALANCE_OBSERVATIONS
import budgeteur.domain.formatCalendarDate
import budgeteur.domain.parseCalendarDate
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.datePath
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
import java.time.LocalDate
import java.util.UUID
import org.jooq.DSLContext

/** Returns false when the account has no observation on the date. */
private fun DSLContext.deleteObservation(userId: String, accountId: UUID, asOf: LocalDate) =
    deleteFrom(BALANCE_OBSERVATIONS)
        .where(
            BALANCE_OBSERVATIONS.ACCOUNT_ID.eq(accountId),
            BALANCE_OBSERVATIONS.USER_ID.eq(userId),
            BALANCE_OBSERVATIONS.AS_OF.eq(asOf.formatCalendarDate()),
        )
        .execute() > 0

fun Route.deleteBalanceObservation(db: Db) =
    delete("/api/accounts/{id}/observations/{asOf}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val asOf =
                    withError(DomainError::ValidationFailed) {
                        parseCalendarDate(call.parameters["asOf"].orEmpty())
                    }
                ensure(db.sql { deleteObservation(userId, id, asOf) }) {
                    DomainError.NotFound("No balance on $asOf for account $id")
                }

                call.log.info("Deleted the balance on $asOf for account $id", "accountId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete an account's balance"
            description =
                "Deletes the balance recorded for the account on a date. The previous balance " +
                    "becomes current; deleting the last leaves the balance unknown. Returns 204 " +
                    "on success."
            tag("Accounts")
            uuidPath("id")
            datePath("asOf")
            responses {
                noContent()
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
