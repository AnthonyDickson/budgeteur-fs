package budgeteur.feature.status

import budgeteur.shared.Clock
import budgeteur.shared.Db
import budgeteur.shared.Json
import budgeteur.shared.LogEntry
import budgeteur.shared.LogLevel
import budgeteur.shared.log
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable

object GetStatus {
    const val PATH = "/api/status"
    private const val HEALTHY = "healthy"
    private const val UNHEALTHY = "unhealthy"
    private val probeTimeout = Duration.ofSeconds(2)

    @Serializable
    data class DatabaseHealth(
        /** `healthy` when the probe succeeded, `unhealthy` otherwise. */
        val status: String,
        /** Present only when the probe failed. */
        val error: String?,
    )

    @Serializable
    data class StatusResponse(
        val version: String,
        val environment: String,
        /** UTC instant the server process started, ISO-8601. */
        val startedAt: String,
        val uptimeSeconds: Long,
        val uptime: String,
        val database: DatabaseHealth,
    )

    fun formatUptime(uptime: Duration): String =
        when (val days = uptime.toDays()) {
            0L -> "${uptime.toHoursPart()}h ${uptime.toMinutesPart()}m ${uptime.toSecondsPart()}s"
            else -> "${days}d ${uptime.toHoursPart()}h ${uptime.toMinutesPart()}m"
        }

    /** The probe's outcome plus what to log about it; the caller does the logging. */
    private suspend fun checkDatabase(db: Db): Pair<DatabaseHealth, List<LogEntry>> =
        withTimeoutOrNull(probeTimeout.toMillis()) {
            try {
                db.run { c -> c.createStatement().use { it.executeQuery("SELECT 1").close() } }
                DatabaseHealth(HEALTHY, null) to emptyList()
            } catch (e: java.sql.SQLException) {
                DatabaseHealth(UNHEALTHY, "database unreachable") to
                    listOf(LogEntry(LogLevel.Warning, "Database health probe failed", mapOf("exception" to e.message)))
            }
        } ?: (DatabaseHealth(UNHEALTHY, "database probe timed out") to
            listOf(LogEntry(LogLevel.Warning, "Database health probe timed out", emptyMap())))

    private val version: String =
        GetStatus::class.java.`package`?.implementationVersion ?: "unknown"

    fun Route.getStatus(db: Db, environment: String, startedAt: Instant, clock: Clock) =
        get(PATH) {
            val (database, entries) = checkDatabase(db)
            call.log.addAll(entries)
            val uptime = Duration.between(startedAt, clock())
            val response =
                StatusResponse(
                    version = version,
                    environment = environment,
                    startedAt = startedAt.toString(),
                    uptimeSeconds = uptime.seconds,
                    uptime = formatUptime(uptime),
                    database = database,
                )
            val status = if (database.status == HEALTHY) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable
            Json.write(call, response, status)
        }
}
