package budgeteur.feature.imports

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.importEndpoints(db: Db) {
    importStatements(db)
}
