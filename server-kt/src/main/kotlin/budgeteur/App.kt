package budgeteur

import budgeteur.feature.auth.authEndpoints
import budgeteur.feature.auth.loginAttemptCookie
import budgeteur.feature.status.STATUS_PATH
import budgeteur.feature.status.getStatus
import budgeteur.feature.tag.tagEndpoints
import budgeteur.shared.BEARER_AUTH
import budgeteur.shared.Clock
import budgeteur.shared.CookieSettings
import budgeteur.shared.Db
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import budgeteur.shared.RequestLogging
import budgeteur.shared.apiErrors
import budgeteur.shared.apiJson
import budgeteur.shared.authenticated
import budgeteur.shared.respondError
import budgeteur.shared.userSession
import budgeteur.shared.userSessionCookie
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.AuthenticationConfig
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.path
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.server.sessions.Sessions
import java.time.Instant

/** Everything the app needs from outside. The server and the test host each build one. */
class Dependencies(
    val db: Db,
    val clock: Clock,
    val environment: String,
    val startedAt: Instant,
    /** The provider the SPA logs in through: a real one in the server, a fake in tests. */
    val oidc: OidcClient,
    val login: LoginConfig,
    val callbackPath: String,
    val cookies: CookieSettings,
    /** Registers the [BEARER_AUTH] provider: JWT bearer in the server, a fake in tests. */
    val configureBearer: AuthenticationConfig.() -> Unit,
)

fun Application.budgeteur(deps: Dependencies) {
    install(RequestLogging) { quietPaths = setOf(STATUS_PATH) }
    install(ContentNegotiation) { json(apiJson) }
    install(StatusPages) { apiErrors() }
    install(Sessions) {
        userSessionCookie(deps.cookies)
        loginAttemptCookie(deps.cookies, deps.callbackPath)
    }
    install(Authentication) {
        userSession(deps.clock)
        deps.configureBearer(this)
    }

    routing {
        getStatus(deps.db, deps.environment, deps.startedAt, deps.clock)
        authEndpoints(deps.oidc, deps.login, deps.callbackPath, deps.clock)

        authenticated { tagEndpoints(deps.db) }

        // Unknown API paths get a JSON 404. Ktor ranks the literal routes above
        // this tailcard, whatever the order of registration.
        route("/api/{...}") {
            handle {
                call.respondError(
                    HttpStatusCode.NotFound,
                    "Not Found",
                    "No API endpoint matches ${call.request.path()}",
                )
            }
        }
    }
}
