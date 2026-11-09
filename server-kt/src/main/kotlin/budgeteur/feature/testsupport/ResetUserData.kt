package budgeteur.feature.testsupport

import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.BALANCE_SHEET_ITEMS
import budgeteur.data.db.tables.references.RULES
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.shared.Db
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.openapi.hide

/**
 * Deletes all of the current user's data, so each E2E test starts empty. Registered in Development
 * only, so it can never be reached against real data. Categorisations go with their transactions,
 * by cascade, and observations with their items and accounts.
 */
fun Route.resetUserData(db: Db) =
    delete("/api/test/user-data") {
            call.handle {
                val userId = call.userId
                val deleted = db.transaction {
                    mapOf(
                        "transactionsDeleted" to
                            deleteFrom(TRANSACTIONS)
                                .where(TRANSACTIONS.USER_ID.eq(userId))
                                .execute(),
                        "accountsDeleted" to
                            deleteFrom(ACCOUNTS).where(ACCOUNTS.USER_ID.eq(userId)).execute(),
                        "itemsDeleted" to
                            deleteFrom(BALANCE_SHEET_ITEMS)
                                .where(BALANCE_SHEET_ITEMS.USER_ID.eq(userId))
                                .execute(),
                        // Transfer rules have no tag, so they do not go with the tags.
                        "rulesDeleted" to
                            deleteFrom(RULES).where(RULES.USER_ID.eq(userId)).execute(),
                        "tagsDeleted" to deleteFrom(TAGS).where(TAGS.USER_ID.eq(userId)).execute(),
                    )
                }

                call.log.info("Reset user data", *deleted.toList().toTypedArray())
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .hide()
