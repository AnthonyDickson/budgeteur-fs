package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensure
import budgeteur.data.recordItemValue
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

fun Route.recordItemObservation(db: Db, clock: () -> Instant) =
    post("/api/balance-sheet/items/{id}/observations") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val observation = call.receiveOrRaise<ItemObservationRequest>().parse(clock())

                val item = db.transaction {
                    ensure(itemExists(userId, id)) {
                        DomainError.NotFound("Balance sheet item $id not found")
                    }
                    recordItemValue(userId, id, observation)
                    checkNotNull(findItem(userId, id))
                }

                call.log.info(
                    "Recorded a value for balance sheet item $id",
                    "balanceSheetItemId" to id,
                )
                call.respond(item.toResponse())
            }
        }
        .describe {
            summary = "Record a balance sheet item's value"
            description =
                "Records the item's value as of a date, replacing any value on that date. Returns " +
                    "the item with its current value: the latest by as-of date, so an older value " +
                    "does not replace a newer one."
            tag("Balance Sheets")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<ItemObservationRequest>()
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
