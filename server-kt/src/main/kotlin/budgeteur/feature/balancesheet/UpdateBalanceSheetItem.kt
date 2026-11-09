package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensureNotNull
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.requireAll
import budgeteur.domain.BalanceSheetItem
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

/** Replaces the name and term, leaving the side, close date and values alone. */
private fun DSLContext.updateItem(userId: String, item: BalanceSheetItem) {
    update(BALANCE_SHEET_ITEMS)
        .set(BALANCE_SHEET_ITEMS.NAME, item.name.value)
        .set(BALANCE_SHEET_ITEMS.TERM, item.term.name)
        .where(BALANCE_SHEET_ITEMS.ID.eq(item.id), BALANCE_SHEET_ITEMS.USER_ID.eq(userId))
        .execute()
}

fun Route.updateBalanceSheetItem(db: Db) =
    put("/api/balance-sheet/items/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val request = call.receiveOrRaise<UpdateBalanceSheetItemRequest>()

                val updated = db.transaction {
                    // The update builds on the existing item, which keeps its side and close date.
                    val existing =
                        ensureNotNull(findItem(userId, id)) {
                            DomainError.NotFound("Could not find the balance sheet item $id")
                        }
                    val item = request.parse(existing.item)
                    requireAll({ requireUniqueItem(userId, item) })
                    updateItem(userId, item)
                    checkNotNull(findItem(userId, id))
                }

                call.log.info("Updated balance sheet item $id", "balanceSheetItemId" to id)
                call.respond(updated.toResponse())
            }
        }
        .describe {
            summary = "Update a balance sheet item"
            description =
                "Replaces a balance sheet item's name and term. Its side is fixed at creation, its " +
                    "values are recorded as observations, and it is closed and reopened separately."
            tag("Balance Sheets")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<UpdateBalanceSheetItemRequest>()
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
