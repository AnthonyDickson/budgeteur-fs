package budgeteur

import arrow.core.getOrElse
import budgeteur.shared.Auth
import budgeteur.shared.Config
import budgeteur.shared.Db
import budgeteur.shared.Migrations
import budgeteur.shared.systemClock
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import java.lang.management.ManagementFactory
import java.time.Instant
import kotlin.system.exitProcess

/** The imperative shell: read config, migrate, start serving. */
fun main() {
    val config =
        Config.load(System.getenv()).getOrElse { failures ->
            System.err.println("The server refused to start: configuration validation failed.")
            failures.forEach { System.err.println("  - $it") }
            exitProcess(1)
        }

    val db = Db(config.databaseUrl)
    Migrations.run(db).forEach { println("Applied migration $it") }

    val deps =
        Dependencies(
            db = db,
            clock = systemClock,
            environment = config.environment,
            startedAt = Instant.ofEpochMilli(ManagementFactory.getRuntimeMXBean().startTime),
            configureAuth = { Auth.bearer(this, config.oidc) },
        )

    embeddedServer(Netty, port = config.port) { budgeteur(deps) }.start(wait = true)
}
