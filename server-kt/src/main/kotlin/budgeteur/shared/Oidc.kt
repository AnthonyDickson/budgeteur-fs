package budgeteur.shared

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.proc.BadJOSEException
import com.nimbusds.oauth2.sdk.AuthorizationCode
import com.nimbusds.oauth2.sdk.AuthorizationCodeGrant
import com.nimbusds.oauth2.sdk.ResponseType
import com.nimbusds.oauth2.sdk.Scope
import com.nimbusds.oauth2.sdk.TokenRequest
import com.nimbusds.oauth2.sdk.auth.ClientSecretPost
import com.nimbusds.oauth2.sdk.auth.Secret
import com.nimbusds.oauth2.sdk.http.HTTPRequest
import com.nimbusds.oauth2.sdk.id.ClientID
import com.nimbusds.oauth2.sdk.id.Issuer
import com.nimbusds.oauth2.sdk.id.State
import com.nimbusds.oauth2.sdk.pkce.CodeChallengeMethod
import com.nimbusds.oauth2.sdk.pkce.CodeVerifier
import com.nimbusds.openid.connect.sdk.AuthenticationRequest
import com.nimbusds.openid.connect.sdk.AuthenticationResponseParser
import com.nimbusds.openid.connect.sdk.Nonce
import com.nimbusds.openid.connect.sdk.OIDCTokenResponseParser
import com.nimbusds.openid.connect.sdk.op.OIDCProviderMetadata
import com.nimbusds.openid.connect.sdk.validators.IDTokenValidator
import java.net.URI
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/** The secrets of a login in progress, which its callback must match. */
@Serializable
data class PendingAuthorization(val state: String, val nonce: String, val codeVerifier: String)

/** Where to send the user to log in, and what the callback must match. */
class AuthorizationStart(val uri: URI, val pending: PendingAuthorization)

/**
 * The OIDC authorization code flow, from this server's side. The login slice keeps
 * [PendingAuthorization] between the two steps; the test host substitutes a fake provider.
 */
interface OidcClient {
    /** Starts a login whose callback is [redirectUri]. */
    fun startAuthorization(redirectUri: URI): AuthorizationStart

    /**
     * Completes the login that [pending] started, from the [callback] the provider redirected to,
     * and returns the user's id (the `sub` claim). Raises a reason when the provider reports an
     * error or the response does not match the login.
     */
    context(_: Raise<String>)
    suspend fun completeAuthorization(
        callback: URI,
        redirectUri: URI,
        pending: PendingAuthorization,
    ): String
}

/** The [OidcClient] for a real provider, through the Nimbus OAuth 2.0 / OIDC SDK. */
class NimbusOidcClient(authority: String, clientId: String, clientSecret: String) : OidcClient {
    private val issuer = Issuer(authority)
    private val clientId = ClientID(clientId)
    private val clientSecret = Secret(clientSecret)

    // Resolved on first use rather than at startup, so the server starts while the provider is
    // down. A failed resolution is retried on the next use.
    private val metadata: OIDCProviderMetadata by lazy {
        OIDCProviderMetadata.resolve(issuer, TIMEOUT_MS, TIMEOUT_MS)
    }

    /** Caches the provider's signing keys. */
    private val idTokenValidator by lazy {
        IDTokenValidator(issuer, this.clientId, JWSAlgorithm.RS256, metadata.jwkSetURI.toURL())
    }

    /** The provider's signing keys, which also sign its bearer tokens. */
    val jwkSetUri: URI
        get() = metadata.jwkSetURI

    override fun startAuthorization(redirectUri: URI): AuthorizationStart {
        val state = State()
        val nonce = Nonce()
        val codeVerifier = CodeVerifier()
        val request =
            AuthenticationRequest.Builder(ResponseType.CODE, SCOPE, clientId, redirectUri)
                .endpointURI(metadata.authorizationEndpointURI)
                .state(state)
                .nonce(nonce)
                .codeChallenge(codeVerifier, CodeChallengeMethod.S256)
                .build()
        return AuthorizationStart(
            request.toURI(),
            PendingAuthorization(state.value, nonce.value, codeVerifier.value),
        )
    }

    context(_: Raise<String>)
    override suspend fun completeAuthorization(
        callback: URI,
        redirectUri: URI,
        pending: PendingAuthorization,
    ): String {
        val response = AuthenticationResponseParser.parse(callback)
        if (!response.indicatesSuccess()) {
            val error = response.toErrorResponse().errorObject
            raise("the provider refused: ${error.description ?: error.code}")
        }
        ensure(response.state?.value == pending.state) {
            "the response does not belong to this login"
        }
        val code =
            ensureNotNull(response.toSuccessResponse().authorizationCode) {
                "the response has no authorization code"
            }
        return withContext(Dispatchers.IO) { exchange(code, redirectUri, pending) }
    }

    /** Trades the code for an ID token and returns its subject. Blocks on the provider. */
    context(_: Raise<String>)
    private fun exchange(
        code: AuthorizationCode,
        redirectUri: URI,
        pending: PendingAuthorization,
    ): String {
        val request =
            TokenRequest.Builder(
                    metadata.tokenEndpointURI,
                    ClientSecretPost(clientId, clientSecret),
                    AuthorizationCodeGrant(code, redirectUri, CodeVerifier(pending.codeVerifier)),
                )
                .build()
        val response = OIDCTokenResponseParser.parse(request.toHTTPRequest().send())
        if (!response.indicatesSuccess()) {
            val error = response.toErrorResponse().errorObject
            raise("the token request failed: ${error.description ?: error.code}")
        }
        val idToken = response.toSuccessResponse().tokens.toOIDCTokens().idToken
        val claims =
            try {
                idTokenValidator.validate(idToken, Nonce(pending.nonce))
            } catch (e: BadJOSEException) {
                raise("the ID token is invalid: ${e.message}")
            }
        return claims.subject.value
    }

    private companion object {
        const val TIMEOUT_MS = 5_000
        val SCOPE = Scope("openid", "profile", "email")
    }
}

/**
 * Accepts any TLS certificate and host name on outgoing HTTPS connections, for the development
 * provider's self-signed certificate. Development only: it disables TLS verification process wide,
 * and the provider is the only host this server calls. Nimbus sets its own defaults on each
 * connection; the bearer token key fetches use [HttpsURLConnection]'s.
 */
fun trustAnyCertificateForDevelopment() {
    val trustAll =
        object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = Unit

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = Unit

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
    val socketFactory =
        SSLContext.getInstance("TLS")
            .apply { init(null, arrayOf<TrustManager>(trustAll), SecureRandom()) }
            .socketFactory
    val anyHost = HostnameVerifier { _, _ -> true }
    HTTPRequest.setDefaultSSLSocketFactory(socketFactory)
    HTTPRequest.setDefaultHostnameVerifier(anyHost)
    HttpsURLConnection.setDefaultSSLSocketFactory(socketFactory)
    HttpsURLConnection.setDefaultHostnameVerifier(anyHost)
}
