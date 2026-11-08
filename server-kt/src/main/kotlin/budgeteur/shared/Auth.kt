package budgeteur.shared

import arrow.core.Either
import arrow.core.right
import arrow.core.left
import com.auth0.jwk.JwkProviderBuilder
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.auth.AuthenticationConfig
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.principal
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The authenticated user. Every query filters by [userId]. */
data class UserPrincipal(val userId: String)

object Auth {
    /** The name every authenticated route is registered under. */
    const val PROVIDER = "user"

    fun userId(call: ApplicationCall): Either<DomainError, String> =
        call.principal<UserPrincipal>()?.userId?.right() ?: DomainError.Unauthorised.left()

    private fun jwksUri(authority: String): URI {
        val discovery = URI("${authority.trimEnd('/')}/.well-known/openid-configuration")
        val body =
            HttpClient.newHttpClient()
                .send(HttpRequest.newBuilder(discovery).build(), HttpResponse.BodyHandlers.ofString())
                .body()
        val jwks = apiJson.parseToJsonElement(body).jsonObject.getValue("jwks_uri").jsonPrimitive.content
        return URI(jwks)
    }

    /**
     * Bearer tokens signed by the OIDC provider. Fetches the provider's
     * discovery document once, at startup.
     */
    fun bearer(config: AuthenticationConfig, oidc: OidcConfig) {
        val jwkProvider =
            JwkProviderBuilder(jwksUri(oidc.authority).toURL())
                .cached(10, 24, TimeUnit.HOURS)
                .rateLimited(10, 1, TimeUnit.MINUTES)
                .build()

        config.jwt(PROVIDER) {
            verifier(jwkProvider, oidc.authority) {
                // Authelia does not put an aud claim in access tokens.
                if (oidc.validAudiences.isNotEmpty()) withAnyOfAudience(*oidc.validAudiences.toTypedArray())
            }
            validate { credential -> credential.payload.subject?.let(::UserPrincipal) }
            challenge { _, _ -> call.respondError(HttpStatusCode.Unauthorized, "Unauthorized", "Authentication required") }
        }
    }
}
