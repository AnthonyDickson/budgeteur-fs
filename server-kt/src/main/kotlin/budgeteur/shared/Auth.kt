package budgeteur.shared

import com.auth0.jwk.JwkProvider
import com.auth0.jwk.JwkProviderBuilder
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.auth.AuthenticationConfig
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.session
import io.ktor.server.routing.Route
import io.ktor.server.sessions.SameSite
import io.ktor.server.sessions.SessionTransportTransformerEncrypt
import io.ktor.server.sessions.SessionsConfig
import io.ktor.server.sessions.cookie
import io.ktor.server.sessions.sameSite
import io.ktor.server.sessions.sessions
import io.ktor.server.sessions.set
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.serialization.Serializable

/** The authenticated user. Every query filters by [userId]. */
data class UserPrincipal(val userId: String)

/** The SPA's session cookie. */
const val SESSION_AUTH = "session"

/** Bearer tokens from the provider, for API clients such as the API docs. */
const val BEARER_AUTH = "bearer"

/** Routes that need a user, signed in through either the session cookie or a bearer token. */
fun Route.authenticated(build: Route.() -> Unit): Route =
    authenticate(SESSION_AUTH, BEARER_AUTH, build = build)

suspend fun ApplicationCall.respondUnauthorized() =
    respondError(HttpStatusCode.Unauthorized, "Unauthorized", "Authentication required")

/**
 * A signed-in user's session, kept in an encrypted cookie. The cookie lasts until the browser
 * closes; [expiresAt] (epoch seconds) ends the session earlier and cannot be altered by the client.
 */
@Serializable
data class UserSession(val userId: String, val expiresAt: Long) {
    fun isActive(now: Instant): Boolean = now.epochSecond < expiresAt

    companion object {
        /** A session ends after this long without a request. */
        val LIFETIME: Duration = Duration.ofHours(1)

        fun start(userId: String, now: Instant) =
            UserSession(userId, now.plus(LIFETIME).epochSecond)
    }
}

/** Encrypts and signs the auth cookies. */
class CookieSettings(val keys: SessionKeys, val secure: Boolean) {
    fun transformer() = SessionTransportTransformerEncrypt(keys.encryption, keys.signing)
}

fun SessionsConfig.userSessionCookie(settings: CookieSettings) =
    cookie<UserSession>("budgeteur_session") {
        cookie.path = "/"
        cookie.httpOnly = true
        cookie.secure = settings.secure
        cookie.sameSite = SameSite.Lax
        cookie.maxAgeInSeconds = null
        transform(settings.transformer())
    }

/**
 * Registers [SESSION_AUTH]. Requests extend the session: once half its lifetime has passed, the
 * next request renews it, as ASP.NET Core's sliding expiration does, so the cookie is not rewritten
 * on every response.
 */
fun AuthenticationConfig.userSession(clock: Clock) {
    session<UserSession>(SESSION_AUTH) {
        validate { session ->
            val now = clock()
            when {
                !session.isActive(now) -> null
                else -> {
                    val remaining = session.expiresAt - now.epochSecond
                    if (remaining < UserSession.LIFETIME.seconds / 2)
                        sessions.set(UserSession.start(session.userId, now))
                    UserPrincipal(session.userId)
                }
            }
        }
        challenge { call.respondUnauthorized() }
    }
}

/**
 * Registers [BEARER_AUTH] as tokens signed by the OIDC provider. [jwkSetUri] is read on the first
 * token, so the provider need not be up when the server starts.
 */
fun AuthenticationConfig.oidcBearer(
    issuer: String,
    validAudiences: List<String>,
    jwkSetUri: () -> URI,
) {
    val keys by lazy {
        JwkProviderBuilder(jwkSetUri().toURL())
            .cached(10, 24, TimeUnit.HOURS)
            .rateLimited(10, 1, TimeUnit.MINUTES)
            .build()
    }

    jwt(BEARER_AUTH) {
        verifier(JwkProvider { keyId -> keys.get(keyId) }, issuer) {
            // Authelia does not put an aud claim in access tokens.
            if (validAudiences.isNotEmpty()) withAnyOfAudience(*validAudiences.toTypedArray())
        }
        validate { credential -> credential.payload.subject?.let(::UserPrincipal) }
        challenge { _, _ -> call.respondUnauthorized() }
    }
}
