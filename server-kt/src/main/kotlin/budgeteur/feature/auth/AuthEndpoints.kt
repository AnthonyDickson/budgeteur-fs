package budgeteur.feature.auth

import budgeteur.shared.Clock
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import io.ktor.server.routing.Route

/** The SPA's login and logout. API clients use bearer tokens instead. */
fun Route.authEndpoints(oidc: OidcClient, login: LoginConfig, callbackPath: String, clock: Clock) {
    login(oidc, login, callbackPath, clock)
    loginCallback(oidc, callbackPath, clock)
    logout(login)
}
