package budgeteur.feature.auth

import budgeteur.shared.Clock
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.hide

/** The SPA's login and logout. API clients use bearer tokens instead. */
fun Route.authEndpoints(oidc: OidcClient, login: LoginConfig, callbackPath: String, clock: Clock) {
    // Browser redirects, not API endpoints, so the API docs leave them out.
    login(oidc, login, callbackPath, clock).hide()
    loginCallback(oidc, callbackPath, clock).hide()
    logout(login).hide()
}
