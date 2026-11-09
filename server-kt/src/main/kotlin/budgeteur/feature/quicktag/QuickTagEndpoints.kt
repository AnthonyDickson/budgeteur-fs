package budgeteur.feature.quicktag

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.quickTagEndpoints(db: Db) {
    readQueue(db)
    approveSuggestion(db)
    quickTagTransaction(db)
    markTransfer(db)
    dismissTransaction(db)
}
