package budgeteur.feature.rule

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.ruleEndpoints(db: Db) {
    createRule(db)
    readAllRules(db)
    readRule(db)
    updateRule(db)
    deleteRule(db)
}
