package budgeteur

import budgeteur.feature.status.STATUS_PATH
import budgeteur.feature.status.getStatus
import budgeteur.feature.tag.tagEndpoints
import budgeteur.shared.Clock
import budgeteur.shared.Db
import budgeteur.shared.RequestLogging
import budgeteur.shared.USER_AUTH
import budgeteur.shared.apiErrors
import budgeteur.shared.apiJson
import budgeteur.shared.respondError
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.AuthenticationConfig
import io.ktor.server.auth.authenticate
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.path
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import java.time.Instant

/** Everything the app needs from outside. The server and the test host each build one. */
class Dependencies(
    val db: Db,
    val clock: Clock,
    val environment: String,
    val startedAt: Instant,
    /** Registers the [USER_AUTH] provider: JWT bearer in the server, a fake in tests. */
    val configureAuth: AuthenticationConfig.() -> Unit,
)

fun Application.budgeteur(deps: Dependencies) {
    install(RequestLogging) { quietPaths = setOf(STATUS_PATH) }
    install(ContentNegotiation) { json(apiJson) }
    install(StatusPages) { apiErrors() }
    install(Authentication) { deps.configureAuth(this) }

    routing {
        getStatus(deps.db, deps.environment, deps.startedAt, deps.clock)

        authenticate(USER_AUTH) { tagEndpoints(deps.db) }

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
