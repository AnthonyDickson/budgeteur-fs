package budgeteur

import budgeteur.feature.status.GetStatus
import budgeteur.feature.status.GetStatus.getStatus
import budgeteur.feature.tag.tagEndpoints
import budgeteur.shared.ApiError
import budgeteur.shared.Auth
import budgeteur.shared.Clock
import budgeteur.shared.Db
import budgeteur.shared.Json
import budgeteur.shared.RequestLogging
import budgeteur.shared.requestId
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.AuthenticationConfig
import io.ktor.server.auth.authenticate
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
    /** Registers the [Auth.PROVIDER] provider: JWT bearer in the server, a fake in tests. */
    val configureAuth: AuthenticationConfig.() -> Unit,
)

fun Application.budgeteur(deps: Dependencies) {
    install(RequestLogging) { quietPaths = setOf(GetStatus.PATH) }
    install(Authentication) { deps.configureAuth(this) }

    routing {
        getStatus(deps.db, deps.environment, deps.startedAt, deps.clock)

        authenticate(Auth.PROVIDER) {
            tagEndpoints(deps.db)
        }

        // Unknown API paths get a JSON 404. Ktor ranks the literal routes above
        // this tailcard, whatever the order of registration.
        route("/api/{...}") {
            handle {
                Json.write(
                    call,
                    ApiError("Not Found", "No API endpoint matches ${call.request.path()}", 404, call.requestId),
                    HttpStatusCode.NotFound,
                )
            }
        }
    }
}
