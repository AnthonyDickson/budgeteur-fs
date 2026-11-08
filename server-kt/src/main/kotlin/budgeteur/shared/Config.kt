package budgeteur.shared

import arrow.core.Either
import arrow.core.EitherNel
import arrow.core.leftNel
import arrow.core.raise.either
import arrow.core.raise.zipOrAccumulate
import arrow.core.right

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

/**
 * Reads configuration from environment variables, reporting every missing or
 * invalid setting at once so the server refuses to start with a full list.
 */
object Config {
    private fun required(env: Map<String, String>, name: String): EitherNel<String, String> =
        env[name]?.takeIf { it.isNotBlank() }?.right() ?: "$name is required".leftNel()

    private fun port(env: Map<String, String>): EitherNel<String, Int> {
        val raw = env["PORT"] ?: return 5000.right()
        return raw.toIntOrNull()?.takeIf { it in 1..65535 }?.right() ?: "PORT must be a port number, got $raw".leftNel()
    }

    fun load(env: Map<String, String>): Either<List<String>, AppConfig> =
        either {
            zipOrAccumulate(
                { required(env, "BUDGETEUR_DATABASE").bindNel() },
                { required(env, "OIDC_AUTHORITY").bindNel() },
                { port(env).bindNel() },
            ) { database, authority, port ->
                AppConfig(
                    databaseUrl = "jdbc:sqlite:$database",
                    oidc =
                        OidcConfig(
                            authority = authority,
                            validAudiences = env["OIDC_VALID_AUDIENCES"].orEmpty().split(',').map(String::trim).filter(String::isNotEmpty),
                        ),
                    port = port,
                    environment = env["BUDGETEUR_ENVIRONMENT"] ?: "Production",
                )
            }
        }.mapLeft { it.toList() }
}
