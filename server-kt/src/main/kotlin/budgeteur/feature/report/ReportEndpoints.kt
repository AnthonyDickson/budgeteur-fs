package budgeteur.feature.report

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.reportEndpoints(db: Db) {
    readReport(db)
}
