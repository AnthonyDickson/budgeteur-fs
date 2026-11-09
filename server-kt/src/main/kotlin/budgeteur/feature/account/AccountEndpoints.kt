package budgeteur.feature.account

import budgeteur.shared.Db
import io.ktor.server.routing.Route
import java.time.Instant

/**
 * The slice's routes. Shared by the server and the test host so both route the same handlers. The
 * clock bounds as-of and close dates.
 */
fun Route.accountEndpoints(db: Db, clock: () -> Instant) {
    createAccount(db, clock)
    readAccount(db)
    readAllAccounts(db)
    updateAccount(db)
    deleteAccount(db)
    closeAccount(db, clock)
    reopenAccount(db)
    recordBalance(db, clock)
    readBalanceObservations(db)
    deleteBalanceObservation(db)
}
