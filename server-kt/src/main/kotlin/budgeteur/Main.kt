package budgeteur

import arrow.core.getOrElse
import budgeteur.shared.ApiDocsSettings
import budgeteur.shared.CookieSettings
import budgeteur.shared.Db
import budgeteur.shared.NimbusOidcClient
import budgeteur.shared.SessionKeys
import budgeteur.shared.loadConfig
import budgeteur.shared.oidcBearer
import budgeteur.shared.systemClock
import budgeteur.shared.trustAnyCertificateForDevelopment
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import java.lang.management.ManagementFactory
import java.time.Instant
import kotlin.system.exitProcess

/** The imperative shell: read config, migrate, start serving. */
fun main() {
    val config =
        loadConfig(System.getenv()).getOrElse { failures ->
            System.err.println("The server refused to start: configuration validation failed.")
            failures.forEach { System.err.println("  - $it") }
            exitProcess(1)
        }

    // The development provider has a self-signed certificate.
    if (config.isDevelopment) trustAnyCertificateForDevelopment()

    val sessionKeys =
        config.sessionKeyFile?.let(SessionKeys::loadOrCreate)
            ?: SessionKeys.random().also {
                println("BUDGETEUR_SESSION_KEY_FILE is not set: a restart signs every user out")
            }

    val db = Db(config.databaseUrl)
    println("Applied ${db.migrate()} migrations")

    val oidc =
        NimbusOidcClient(config.oidc.authority, config.oidc.clientId, config.oidc.clientSecret)

    val deps =
        Dependencies(
            db = db,
            clock = systemClock,
            environment = config.environment,
            startedAt = Instant.ofEpochMilli(ManagementFactory.getRuntimeMXBean().startTime),
            oidc = oidc,
            login = config.login,
            callbackPath = config.oidc.callbackPath,
            // Development serves plain HTTP.
            cookies = CookieSettings(sessionKeys, secure = !config.isDevelopment),
            configureBearer = {
                oidcBearer(config.oidc.authority, config.oidc.validAudiences) { oidc.jwkSetUri }
            },
            apiDocs =
                config.scalarClientId
                    ?.takeIf { config.isDevelopment }
                    ?.let {
                        ApiDocsSettings(it, { oidc.authorizationEndpoint }, { oidc.tokenEndpoint })
                    },
        )

    embeddedServer(Netty, port = config.port) { budgeteur(deps) }.start(wait = true)
}
