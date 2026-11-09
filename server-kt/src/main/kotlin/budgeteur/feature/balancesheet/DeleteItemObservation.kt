package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensure
import arrow.core.raise.context.withError
import budgeteur.data.db.tables.references.ITEM_OBSERVATIONS
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

fun Route.deleteItemObservation(db: Db) =
    delete("/api/balance-sheet/items/{id}/observations/{asOf}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val asOf =
                    withError(DomainError::ValidationFailed) {
                        parseCalendarDate(call.parameters["asOf"].orEmpty())
                    }

                db.transaction {
                    val dates = readObservations(userId, id).orEmpty().map { it.asOf }
                    ensure(asOf in dates) {
                        DomainError.NotFound("No value on $asOf for balance sheet item $id")
                    }
                    // An item always has a known value, so its last is not deleted.
                    ensure(dates.size > 1) {
                        DomainError.ValidationFailed(
                            "This is the item's only value. An item always has a value, so " +
                                "delete the item instead."
                        )
                    }
                    deleteFrom(ITEM_OBSERVATIONS)
                        .where(
                            ITEM_OBSERVATIONS.ITEM_ID.eq(id),
                            ITEM_OBSERVATIONS.USER_ID.eq(userId),
                            ITEM_OBSERVATIONS.AS_OF.eq(asOf.formatCalendarDate()),
                        )
                        .execute()
                }

                call.log.info(
                    "Deleted the value on $asOf for balance sheet item $id",
                    "balanceSheetItemId" to id,
                )
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete a balance sheet item's value"
            description =
                "Deletes the value recorded for the item on a date, and the previous value becomes " +
                    "current. An item's only value cannot be deleted: delete the item instead. " +
                    "Returns 204 on success."
            tag("Balance Sheets")
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
