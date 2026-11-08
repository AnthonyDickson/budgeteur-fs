package budgeteur.shared

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.context.either
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import arrow.core.raise.context.zipOrAccumulate

data class OidcConfig(
    val authority: String,
    /** Empty disables audience validation. */
    val validAudiences: List<String>,
)

data class AppConfig(
    val databaseUrl: String,
    val oidc: OidcConfig,
    val port: Int,
    val environment: String,
)

private typealias Env = Map<String, String>

context(_: Raise<String>)
private fun Env.required(name: String): String =
    ensureNotNull(get(name)?.takeIf(String::isNotBlank)) { "$name is required" }

context(_: Raise<String>)
private fun Env.port(): Int {
    val raw = get("PORT") ?: return 5000
    return raw.toIntOrNull()?.takeIf { it in 1..65535 }
        ?: raise("PORT must be a port number, got $raw")
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
        { env.port() },
    ) { database, authority, port ->
        AppConfig(
            databaseUrl = "jdbc:sqlite:$database",
            oidc = OidcConfig(authority, env.audiences()),
            port = port,
            environment = env["BUDGETEUR_ENVIRONMENT"] ?: "Production",
        )
    }
}
