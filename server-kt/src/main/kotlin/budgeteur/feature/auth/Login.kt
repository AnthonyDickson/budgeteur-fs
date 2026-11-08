package budgeteur.feature.auth

import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.withError
import budgeteur.shared.Clock
import budgeteur.shared.CookieSettings
import budgeteur.shared.DomainError
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import budgeteur.shared.PendingAuthorization
import budgeteur.shared.UserSession
import budgeteur.shared.handle
import budgeteur.shared.log
import io.ktor.http.encodedPath
import io.ktor.server.application.ApplicationCall
import io.ktor.server.response.respondRedirect
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.sessions.SameSite
import io.ktor.server.sessions.SessionsConfig
import io.ktor.server.sessions.clear
import io.ktor.server.sessions.cookie
import io.ktor.server.sessions.get
import io.ktor.server.sessions.sameSite
import io.ktor.server.sessions.sessions
import io.ktor.server.sessions.set
import io.ktor.server.util.url
import java.net.URI
import java.time.Duration
import kotlinx.serialization.Serializable

const val LOGIN_PATH = "/login"

/** The query parameter naming the page to return to. */
const val RETURN_URL_PARAMETER = "returnUrl"

/** A login in progress, kept in a cookie between `/login` and the provider's callback. */
@Serializable
data class LoginAttempt(val authorization: PendingAuthorization, val returnUrl: String)

/** How long the user has to complete the provider's login form. */
private val LOGIN_ATTEMPT_LIFETIME = Duration.ofMinutes(15)

/**
 * Sent only to the callback. SameSite=Lax still sends it there, since the provider returns with a
 * top-level navigation.
 */
fun SessionsConfig.loginAttemptCookie(settings: CookieSettings, callbackPath: String) =
    cookie<LoginAttempt>("budgeteur_login") {
        cookie.path = callbackPath
        cookie.httpOnly = true
        cookie.secure = settings.secure
        cookie.sameSite = SameSite.Lax
        cookie.maxAgeInSeconds = LOGIN_ATTEMPT_LIFETIME.seconds
        transform(settings.transformer())
    }

/** The callback's absolute URL, on the host the request came to. */
private fun ApplicationCall.callbackUri(callbackPath: String): URI =
    URI(
        url {
            encodedPath = callbackPath
            parameters.clear()
        }
    )

/**
 * Sends the user to the provider to log in, or straight back to the page if they already have a
 * session.
 */
fun Route.login(oidc: OidcClient, login: LoginConfig, callbackPath: String, clock: Clock) =
    get(LOGIN_PATH) {
        val returnUrl =
            resolveReturnUrl(login.returnUrl, call.request.queryParameters[RETURN_URL_PARAMETER])

        if (call.sessions.get<UserSession>()?.isActive(clock()) == true) {
            call.respondRedirect(returnUrl)
        } else {
            val start = oidc.startAuthorization(call.callbackUri(callbackPath))
            call.sessions.set(LoginAttempt(start.pending, returnUrl))
            call.respondRedirect(start.uri.toString())
        }
    }

/**
 * Completes the login the provider redirected back from, starts the session, and returns to the
 * page the login started from. The attempt is used up either way.
 */
fun Route.loginCallback(oidc: OidcClient, callbackPath: String, clock: Clock) =
    get(callbackPath) {
        call.handle {
            val attempt =
                ensureNotNull(call.sessions.get<LoginAttempt>()) {
                    DomainError.ValidationFailed(
                        "Login failed: no login is in progress, or it timed out. Log in again."
                    )
                }
            call.sessions.clear<LoginAttempt>()

            val userId =
                withError({ reason: String ->
                    DomainError.ValidationFailed("Login failed: $reason")
                }) {
                    oidc.completeAuthorization(
                        URI(call.url()),
                        call.callbackUri(callbackPath),
                        attempt.authorization,
                    )
                }

            call.sessions.set(UserSession.start(userId, clock()))
            call.log.info("Logged in", "userId" to userId)
            call.respondRedirect(attempt.returnUrl)
        }
    }
