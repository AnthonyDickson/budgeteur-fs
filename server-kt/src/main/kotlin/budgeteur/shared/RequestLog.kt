package budgeteur.shared

import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.application.hooks.ResponseSent
import io.ktor.server.auth.principal
import io.ktor.server.request.httpMethod
import io.ktor.server.request.path
import io.ktor.util.AttributeKey
import java.time.Instant
import org.slf4j.LoggerFactory
import org.slf4j.event.Level

enum class LogLevel {
    Info,
    Warning,
    Error,
}

data class LogEntry(
    val level: LogLevel,
    val message: String,
    val properties: Map<String, Any?>,
    val timestamp: Instant = Instant.now(),
)

/**
 * Collects a request's log entries so the request is logged once, as one wide event, when its
 * response is sent.
 */
class RequestLog {
    private val entries = mutableListOf<LogEntry>()

    fun info(message: String, vararg props: Pair<String, Any?>) = add(LogLevel.Info, message, props)

    fun warn(message: String, vararg props: Pair<String, Any?>) =
        add(LogLevel.Warning, message, props)

    fun error(message: String, vararg props: Pair<String, Any?>) =
        add(LogLevel.Error, message, props)

    fun snapshot(): List<LogEntry> = synchronized(entries) { entries.toList() }

    private fun add(level: LogLevel, message: String, props: Array<out Pair<String, Any?>>) =
        synchronized(entries) { entries.add(LogEntry(level, message, props.toMap())) }
}

private val requestLogKey = AttributeKey<RequestLog>("RequestLog")

val ApplicationCall.log: RequestLog
    get() = attributes[requestLogKey]

/** Paths to leave out of the log, such as the status probe. */
class RequestLoggingConfig {
    var quietPaths: Set<String> = emptySet()
}

val RequestLogging =
    createApplicationPlugin("RequestLogging", ::RequestLoggingConfig) {
        val logger = LoggerFactory.getLogger("budgeteur.Request")
        val quietPaths = pluginConfig.quietPaths

        onCall { call ->
            call.attributes.put(requestLogKey, RequestLog())
            call.attributes.put(startKey, System.nanoTime())
        }

        on(ResponseSent) { call ->
            val path = call.request.path()
            if (path in quietPaths) return@on
            val entries = call.log.snapshot()
            val elapsedMs = (System.nanoTime() - call.attributes[startKey]) / 1_000_000
            val method = call.request.httpMethod.value
            val status = call.response.status()?.value
            val level =
                when (entries.maxOfOrNull { it.level } ?: LogLevel.Info) {
                    LogLevel.Info -> Level.INFO
                    LogLevel.Warning -> Level.WARN
                    LogLevel.Error -> Level.ERROR
                }
            // The encoder writes each key-value pair as a field of the JSON event.
            logger
                .atLevel(level)
                .addKeyValue("method", method)
                .addKeyValue("path", path)
                .addKeyValue("status", status)
                .addKeyValue("elapsedMs", elapsedMs)
                .addKeyValue("requestId", call.requestId)
                .addKeyValue("user", call.principal<UserPrincipal>()?.userId)
                .addKeyValue("entries", entries.map(LogEntry::toFields))
                .log("$method $path $status in $elapsedMs ms")
        }
    }

private fun LogEntry.toFields(): Map<String, String?> =
    mapOf(
        "level" to level.name,
        "message" to message,
        "timestamp" to timestamp.toString(),
    ) + properties.mapValues { (_, value) -> value?.toString() }

private val startKey = AttributeKey<Long>("RequestStart")
