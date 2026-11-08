package budgeteur.feature.status

import budgeteur.shared.Clock
import budgeteur.shared.Db
import budgeteur.shared.RequestLog
import budgeteur.shared.appVersion
import budgeteur.shared.json
import budgeteur.shared.log
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
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
@JsonSchema.Description("Outcome of the database connectivity probe.")
data class DatabaseHealth(
    @JsonSchema.Description("`healthy` when the probe succeeded, `unhealthy` otherwise.")
    val status: String,
    @JsonSchema.Description("Details of the failure, present only when the probe failed.")
    val error: String?,
)

@Serializable
data class StatusResponse(
    @JsonSchema.Description("The version of the running build.") val version: String,
    @JsonSchema.Description("The environment name, e.g. Development or Production.")
    val environment: String,
    @JsonSchema.Description("UTC instant the server process started.")
    @JsonSchema.Format("date-time")
    val startedAt: String,
    @JsonSchema.Description("Seconds elapsed since the server process started.")
    val uptimeSeconds: Long,
    @JsonSchema.Description("Time since the server process started, for people to read.")
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
        } catch (e: DataAccessException) {
            // jOOQ wraps the driver's exceptions, including failures to connect.
            log.warn("Database health probe failed", "exception" to e.message)
            DatabaseHealth(UNHEALTHY, "database unreachable")
        }
    }
        ?: DatabaseHealth(UNHEALTHY, "database probe timed out").also {
            log.warn("Database health probe timed out")
        }

fun Route.getStatus(db: Db, environment: String, startedAt: Instant, clock: Clock) =
    get(STATUS_PATH) {
            val database = checkDatabase(db, call.log)
            val uptime = Duration.between(startedAt, clock())
            val response =
                StatusResponse(
                    version = appVersion,
                    environment = environment,
                    startedAt = startedAt.toString(),
                    uptimeSeconds = uptime.seconds,
                    uptime = formatUptime(uptime),
                    database = database,
                )
            val status =
                if (database.status == HEALTHY) HttpStatusCode.OK
                else HttpStatusCode.ServiceUnavailable
            call.respond(status, response)
        }
        .describe {
            summary = "Service status"
            description =
                "Reports the running version, uptime, and database health. Returns 503 when the database is unreachable."
            tag("Status")
            responses {
                json<StatusResponse>(HttpStatusCode.OK)
                json<StatusResponse>(HttpStatusCode.ServiceUnavailable)
            }
        }
