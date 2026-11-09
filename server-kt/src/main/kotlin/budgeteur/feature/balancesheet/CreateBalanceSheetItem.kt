package budgeteur.feature.balancesheet

import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.recordItemValue
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

fun Route.createBalanceSheetItem(db: Db, clock: () -> Instant) =
    post("/api/balance-sheet/items") {
            call.handle {
                val userId = call.userId
                val (item, first) =
                    call.receiveOrRaise<CreateBalanceSheetItemRequest>().parse(newId(), clock())

                val created = db.transaction {
                    requireAll({ requireUniqueItem(userId, item) })
                    insertInto(BALANCE_SHEET_ITEMS).set(item.toRecord(userId)).execute()
                    recordItemValue(userId, item.id, first)
                    checkNotNull(findItem(userId, item.id))
                }

                call.log.info(
                    "Created balance sheet item ${item.id}",
                    "balanceSheetItemId" to item.id,
                )
                call.respond(HttpStatusCode.Created, created.toResponse())
            }
        }
        .describe {
            summary = "Create a balance sheet item"
            description =
                "Creates a balance sheet item with its first value and returns it with status 201."
            tag("Balance Sheets")
            requestBody {
                required = true
                schema = jsonSchema<CreateBalanceSheetItemRequest>()
            }
            responses {
                json<BalanceSheetItemResponse>(HttpStatusCode.Created)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
