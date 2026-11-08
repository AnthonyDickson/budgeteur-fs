package budgeteur.feature.rule

import budgeteur.shared.handle
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get

/**
 * A stub until the PoC has a rules slice: every user has no rules. The client's tagging page loads
 * tags and rules together, so without it the page cannot show tags.
 */
fun Route.readAllRules() = get("/api/rules") { call.handle { call.respond(emptyList<String>()) } }
