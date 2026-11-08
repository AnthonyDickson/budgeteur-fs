package budgeteur.feature.status

import budgeteur.shared.Clock
import budgeteur.shared.Db
import budgeteur.shared.RequestLog
import budgeteur.shared.log
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import java.sql.SQLException
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import org.jooq.exception.DataAccessException

const val STATUS_PATH = "/api/status"

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

private suspend fun checkDatabase(db: Db, log: RequestLog): DatabaseHealth =
    withTimeoutOrNull(probeTimeout.toMillis()) {
        try {
            db.sql { selectOne().fetch() }
            DatabaseHealth(HEALTHY, null)
        } catch (e: SQLException) {
            // Opening the connection throws the driver's exception; queries throw jOOQ's.
            log.warn("Database health probe failed", "exception" to e.message)
            DatabaseHealth(UNHEALTHY, "database unreachable")
        } catch (e: DataAccessException) {
            log.warn("Database health probe failed", "exception" to e.message)
            DatabaseHealth(UNHEALTHY, "database unreachable")
        }
    } ?: DatabaseHealth(UNHEALTHY, "database probe timed out").also { log.warn("Database health probe timed out") }

private val version: String = StatusResponse::class.java.`package`?.implementationVersion ?: "unknown"

fun Route.getStatus(db: Db, environment: String, startedAt: Instant, clock: Clock) =
    get(STATUS_PATH) {
        val database = checkDatabase(db, call.log)
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
        call.respond(status, response)
    }
