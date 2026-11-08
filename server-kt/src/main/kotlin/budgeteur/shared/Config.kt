package budgeteur.shared

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.either
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import arrow.core.raise.context.zipOrAccumulate
import java.net.URI
import java.nio.file.Path

data class OidcConfig(
    val authority: String,
    val clientId: String,
    val clientSecret: String,
    /** The path on this server that the provider redirects back to after a login. */
    val callbackPath: String,
    /** Empty disables audience validation of bearer tokens. */
    val validAudiences: List<String>,
)

data class LoginConfig(
    /**
     * Where a login returns to, and the base the client's page is resolved against. Absolute, since
     * the client may be served from another origin, as in development.
     */
    val returnUrl: String,
    /**
     * The provider's logout page, which `/logout` redirects to so the provider session ends with
     * the app's. Without it the next login skips the provider's login form.
     */
    val logoutUrl: String?,
)

data class AppConfig(
    val databaseUrl: String,
    val oidc: OidcConfig,
    val login: LoginConfig,
    /** Holds the keys that encrypt the session cookie. Without it they last until a restart. */
    val sessionKeyFile: Path?,
    val port: Int,
    val environment: String,
) {
    val isDevelopment: Boolean
        get() = environment == "Development"
}

private typealias Env = Map<String, String>

context(_: Raise<String>)
private fun Env.required(name: String): String =
    ensureNotNull(optional(name)) { "$name is required" }

private fun Env.optional(name: String): String? = get(name)?.takeIf(String::isNotBlank)

context(_: Raise<String>)
private fun Env.port(): Int {
    val raw = get("PORT") ?: return 5000
    return raw.toIntOrNull()?.takeIf { it in 1..65535 }
        ?: raise("PORT must be a port number, got $raw")
}

context(_: Raise<String>)
private fun Env.callbackPath(): String {
    val path = optional("OIDC_CALLBACK_PATH") ?: return "/signin-oidc"
    ensure(path.startsWith("/")) { "OIDC_CALLBACK_PATH must start with /, got $path" }
    return path
}

context(_: Raise<String>)
private fun absoluteUrl(name: String, value: String): String {
    val uri = runCatching { URI(value) }.getOrNull()
    ensure(uri != null && uri.scheme in setOf("http", "https") && uri.host != null) {
        "$name must be an absolute http(s) URL, got $value"
    }
    return value
}

private fun Env.audiences(): List<String> =
    get("OIDC_VALID_AUDIENCES").orEmpty().split(',').map(String::trim).filter(String::isNotEmpty)

/**
 * Reads configuration from environment variables, reporting every missing or invalid setting at
 * once so the server refuses to start with a full list.
 */
fun loadConfig(env: Env): Either<NonEmptyList<String>, AppConfig> = either {
    zipOrAccumulate(
        { env.required("BUDGETEUR_DATABASE") },
        { env.required("OIDC_AUTHORITY") },
        { env.required("OIDC_CLIENT_ID") },
        { env.required("OIDC_CLIENT_SECRET") },
        { env.callbackPath() },
        { absoluteUrl("LOGIN_RETURN_URL", env.required("LOGIN_RETURN_URL")) },
        { env.optional("OIDC_LOGOUT_URL")?.let { absoluteUrl("OIDC_LOGOUT_URL", it) } },
        { env.port() },
    ) { database, authority, clientId, clientSecret, callbackPath, returnUrl, logoutUrl, port ->
        AppConfig(
            databaseUrl = "jdbc:sqlite:$database",
            oidc = OidcConfig(authority, clientId, clientSecret, callbackPath, env.audiences()),
            login = LoginConfig(returnUrl, logoutUrl),
            sessionKeyFile = env.optional("BUDGETEUR_SESSION_KEY_FILE")?.let(Path::of),
            port = port,
            environment = env["BUDGETEUR_ENVIRONMENT"] ?: "Production",
        )
    }
}
