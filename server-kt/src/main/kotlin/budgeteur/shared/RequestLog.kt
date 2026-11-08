package budgeteur.shared

import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.application.hooks.ResponseSent
import io.ktor.server.auth.principal
import io.ktor.server.request.httpMethod
import io.ktor.server.request.path
import io.ktor.util.AttributeKey
import java.time.Instant
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.slf4j.LoggerFactory

enum class LogLevel { Info, Warning, Error }

data class LogEntry(
    val level: LogLevel,
    val message: String,
    val properties: Map<String, Any?>,
    val timestamp: Instant = Instant.now(),
)

/**
 * Collects a request's log entries so the request is logged once, as one wide
 * event, when its response is sent.
 */
class RequestLog {
    private val entries = mutableListOf<LogEntry>()

    fun info(message: String, vararg props: Pair<String, Any?>) = add(LogLevel.Info, message, props)

    fun warn(message: String, vararg props: Pair<String, Any?>) = add(LogLevel.Warning, message, props)

    fun error(message: String, vararg props: Pair<String, Any?>) = add(LogLevel.Error, message, props)

    fun addAll(more: List<LogEntry>) = synchronized(entries) { entries.addAll(more) }

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
            val event =
                buildJsonObject {
                    put("method", call.request.httpMethod.value)
                    put("path", path)
                    put("status", call.response.status()?.value)
                    put("elapsedMs", elapsedMs)
                    put("user", call.principal<UserPrincipal>()?.userId)
                    put(
                        "entries",
                        buildJsonArray {
                            entries.forEach { entry ->
                                add(
                                    buildJsonObject {
                                        put("level", entry.level.name)
                                        put("message", entry.message)
                                        put("timestamp", entry.timestamp.toString())
                                        entry.properties.forEach { (k, v) -> put(k, JsonPrimitive(v?.toString())) }
                                    },
                                )
                            }
                        },
                    )
                }
            when (entries.maxOfOrNull { it.level } ?: LogLevel.Info) {
                LogLevel.Info -> logger.info("{}", event)
                LogLevel.Warning -> logger.warn("{}", event)
                LogLevel.Error -> logger.error("{}", event)
            }
        }
    }

private val startKey = AttributeKey<Long>("RequestStart")
