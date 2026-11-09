package budgeteur

import budgeteur.feature.account.accountEndpoints
import budgeteur.feature.auth.authEndpoints
import budgeteur.feature.auth.loginAttemptCookie
import budgeteur.feature.autotag.autoTagEndpoints
import budgeteur.feature.balancesheet.balanceSheetDevelopmentEndpoints
import budgeteur.feature.balancesheet.balanceSheetEndpoints
import budgeteur.feature.imports.importEndpoints
import budgeteur.feature.rule.ruleEndpoints
import budgeteur.feature.status.STATUS_PATH
import budgeteur.feature.status.getStatus
import budgeteur.feature.tag.tagEndpoints
import budgeteur.feature.testsupport.resetUserData
import budgeteur.feature.transaction.transactionDevelopmentEndpoints
import budgeteur.feature.transaction.transactionEndpoints
import budgeteur.shared.ApiDocsSettings
import budgeteur.shared.BEARER_AUTH
import budgeteur.shared.Clock
import budgeteur.shared.CookieSettings
import budgeteur.shared.DEFAULT_BODY_LIMIT
import budgeteur.shared.Db
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import budgeteur.shared.RequestLogging
import budgeteur.shared.SHUTDOWN_TIMEOUT
import budgeteur.shared.TrustedForwardedHeaders
import budgeteur.shared.apiDocs
import budgeteur.shared.apiErrors
import budgeteur.shared.apiJson
import budgeteur.shared.authenticated
import budgeteur.shared.bodyLimit
import budgeteur.shared.clientFiles
import budgeteur.shared.drainCallsOnStop
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
import io.ktor.server.routing.openapi.hide
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.server.sessions.Sessions
import java.nio.file.Path
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
    /** Serves the OpenAPI document and Scalar when present: Development only. */
    val apiDocs: ApiDocsSettings? = null,
    /** The client's build, served with the SPA fallback when present. */
    val webRoot: Path? = null,
)

fun Application.budgeteur(deps: Dependencies) {
    drainCallsOnStop(SHUTDOWN_TIMEOUT)
    install(TrustedForwardedHeaders)
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
        bodyLimit(DEFAULT_BODY_LIMIT)
        getStatus(deps.db, deps.environment, deps.startedAt, deps.clock)
        authEndpoints(deps.oidc, deps.login, deps.callbackPath, deps.clock)
        deps.apiDocs?.let { apiDocs(it) }

        authenticated {
            tagEndpoints(deps.db)
            transactionEndpoints(deps.db)
            accountEndpoints(deps.db, deps.clock)
            balanceSheetEndpoints(deps.db, deps.clock)
            ruleEndpoints(deps.db)
            autoTagEndpoints(deps.db)
            importEndpoints(deps.db)
            // Inspection and test helpers, so they can never be reached against real data.
            if (deps.environment == "Development") {
                transactionDevelopmentEndpoints(deps.db)
                balanceSheetDevelopmentEndpoints(deps.db)
                resetUserData(deps.db)
            }
        }

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
            .hide()

        deps.webRoot?.let { clientFiles(it) }
    }
}
