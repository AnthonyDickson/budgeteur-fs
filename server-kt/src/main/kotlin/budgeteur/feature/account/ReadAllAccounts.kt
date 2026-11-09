package budgeteur.feature.account

import budgeteur.shared.handle
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.hide

/**
 * A stub until the PoC has an accounts slice: every user has no accounts. The client's transaction
 * page loads accounts with its transactions, so without it the page cannot show them. Hidden from
 * the API docs, since its empty list says nothing about an account's shape.
 */
fun Route.readAllAccounts() =
    get("/api/accounts") { call.handle { call.respond(emptyList<String>()) } }.hide()
