package budgeteur.feature.balancesheet

import budgeteur.shared.Db
import io.ktor.server.routing.Route
import java.time.Instant

/**
 * The slice's routes. Shared by the server and the test host so both route the same handlers. The
 * clock bounds as-of and close dates.
 */
fun Route.balanceSheetEndpoints(db: Db, clock: () -> Instant) {
    readBalanceSheet(db)
    createBalanceSheetItem(db, clock)
    readBalanceSheetItem(db)
    updateBalanceSheetItem(db)
    deleteBalanceSheetItem(db)
    closeBalanceSheetItem(db, clock)
    reopenBalanceSheetItem(db)
    recordItemObservation(db, clock)
    readItemObservations(db)
    deleteItemObservation(db)
}

/** Development only: the page reads the whole sheet. */
fun Route.balanceSheetDevelopmentEndpoints(db: Db) {
    readAllBalanceSheetItems(db)
}
