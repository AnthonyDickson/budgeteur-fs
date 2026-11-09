package budgeteur.feature.balancesheet

import arrow.core.raise.context.ensureNotNull
import budgeteur.data.db.tables.references.ITEM_OBSERVATIONS
import budgeteur.data.toObservation
import budgeteur.domain.ItemObservation
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

/** The item's observations, newest first, or null when the user has no item with the id. */
internal fun DSLContext.readObservations(userId: String, itemId: UUID): List<ItemObservation>? =
    if (!itemExists(userId, itemId)) {
        null
    } else {
        selectFrom(ITEM_OBSERVATIONS)
            .where(ITEM_OBSERVATIONS.ITEM_ID.eq(itemId), ITEM_OBSERVATIONS.USER_ID.eq(userId))
            .orderBy(ITEM_OBSERVATIONS.AS_OF.desc())
            .fetch { it.toObservation() }
    }

fun Route.readItemObservations(db: Db) =
    get("/api/balance-sheet/items/{id}/observations") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val observations =
                    ensureNotNull(db.sql { readObservations(userId, id) }) {
                        DomainError.NotFound("Balance sheet item $id not found")
                    }

                call.log.info(
                    "Returned ${observations.size} values for balance sheet item $id",
                    "balanceSheetItemId" to id,
                )
                call.respond(observations.map { it.toResponse() })
            }
        }
        .describe {
            summary = "List a balance sheet item's values"
            description =
                "Returns every value recorded for the item, newest first. The first is the " +
                    "current value."
            tag("Balance Sheets")
            uuidPath("id")
            responses {
                json<List<ItemObservationResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
