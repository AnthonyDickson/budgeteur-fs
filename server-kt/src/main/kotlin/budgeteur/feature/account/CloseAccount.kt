package budgeteur.feature.account

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.ACCOUNTS
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
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.jooq.DSLContext

/** Sets or clears the close date. Returns false when the user has no account with the id. */
internal fun DSLContext.setCloseDate(userId: String, id: UUID, closedOn: LocalDate?): Boolean =
    update(ACCOUNTS)
        .set(ACCOUNTS.CLOSED_ON, closedOn?.formatCalendarDate())
        .where(ACCOUNTS.ID.eq(id), ACCOUNTS.USER_ID.eq(userId))
        .execute() > 0

fun Route.closeAccount(db: Db, clock: () -> Instant) =
    put("/api/accounts/{id}/close-date") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val closedOn = call.receiveOrRaise<CloseAccountRequest>().parse(clock())

                val closed = db.transaction {
                    ensure(setCloseDate(userId, id, closedOn)) {
                        DomainError.NotFound("Account $id not found")
                    }
                    checkNotNull(findAccount(userId, id))
                }

                call.log.info("Closed account $id on $closedOn", "accountId" to id)
                call.respond(closed.toResponse())
            }
        }
        .describe {
            summary = "Close an account"
            description =
                "Sets the date the account was closed. Balance sheets drawn on or after it leave " +
                    "the account out; earlier ones keep it. Returns the account with its current " +
                    "balance."
            tag("Accounts")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<CloseAccountRequest>()
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
