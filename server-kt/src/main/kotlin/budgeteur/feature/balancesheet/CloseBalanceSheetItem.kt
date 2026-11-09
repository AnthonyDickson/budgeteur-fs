package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
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

/** Sets or clears the close date. Returns false when the user has no item with the id. */
internal fun DSLContext.setCloseDate(userId: String, id: UUID, closedOn: LocalDate?): Boolean =
    update(BALANCE_SHEET_ITEMS)
        .set(BALANCE_SHEET_ITEMS.CLOSED_ON, closedOn?.formatCalendarDate())
        .where(BALANCE_SHEET_ITEMS.ID.eq(id), BALANCE_SHEET_ITEMS.USER_ID.eq(userId))
        .execute() > 0

fun Route.closeBalanceSheetItem(db: Db, clock: () -> Instant) =
    put("/api/balance-sheet/items/{id}/close-date") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val closedOn = call.receiveOrRaise<CloseBalanceSheetItemRequest>().parse(clock())

                val closed = db.transaction {
                    ensure(setCloseDate(userId, id, closedOn)) {
                        DomainError.NotFound("Balance sheet item $id not found")
                    }
                    checkNotNull(findItem(userId, id))
                }

                call.log.info(
                    "Closed balance sheet item $id on $closedOn",
                    "balanceSheetItemId" to id,
                )
                call.respond(closed.toResponse())
            }
        }
        .describe {
            summary = "Close a balance sheet item"
            description =
                "Sets the date the item was sold or repaid. Balance sheets drawn on or after it " +
                    "leave the item out; earlier ones keep it. Returns the item with its current " +
                    "value."
            tag("Balance Sheets")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<CloseBalanceSheetItemRequest>()
            }
            responses {
                json<BalanceSheetItemResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
