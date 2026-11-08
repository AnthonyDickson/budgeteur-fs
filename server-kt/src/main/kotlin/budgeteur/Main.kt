package budgeteur

import arrow.core.getOrElse
import budgeteur.shared.oidcBearer
import budgeteur.shared.loadConfig
import budgeteur.shared.Db
import budgeteur.shared.systemClock
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

    val db = Db(config.databaseUrl)
    println("Applied ${db.migrate()} migrations")

    val deps =
        Dependencies(
            db = db,
            clock = systemClock,
            environment = config.environment,
            startedAt = Instant.ofEpochMilli(ManagementFactory.getRuntimeMXBean().startTime),
            configureAuth = { oidcBearer(config.oidc) },
        )

    embeddedServer(Netty, port = config.port) { budgeteur(deps) }.start(wait = true)
}
