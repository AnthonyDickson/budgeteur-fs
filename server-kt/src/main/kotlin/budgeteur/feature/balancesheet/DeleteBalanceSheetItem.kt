package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
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

/** Its values go with it, by cascade. Returns false when the user has no item with the id. */
private fun DSLContext.deleteItem(userId: String, id: UUID): Boolean =
    deleteFrom(BALANCE_SHEET_ITEMS)
        .where(BALANCE_SHEET_ITEMS.ID.eq(id), BALANCE_SHEET_ITEMS.USER_ID.eq(userId))
        .execute() > 0

fun Route.deleteBalanceSheetItem(db: Db) =
    delete("/api/balance-sheet/items/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                ensure(db.sql { deleteItem(userId, id) }) {
                    DomainError.NotFound("Balance sheet item $id not found")
                }

                call.log.info("Deleted balance sheet item $id", "balanceSheetItemId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete a balance sheet item"
            description =
                "Permanently removes a balance sheet item with its values. Returns 204 on success."
            tag("Balance Sheets")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
