package budgeteur.shared

import budgeteur.read
import budgeteur.withTestApp
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.OutputStreamAppender
import ch.qos.logback.core.read.ListAppender
import io.ktor.client.request.get
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.slf4j.LoggerFactory

/** Runs [block] and returns the request log's events, encoded as the console writes them. */
private fun captureRequestLog(block: () -> Unit): List<JsonObject> {
    val root = LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME) as Logger
    @Suppress("UNCHECKED_CAST")
    val encoder = (root.getAppender("STDOUT") as OutputStreamAppender<ILoggingEvent>).encoder
    val logger = LoggerFactory.getLogger("budgeteur.Request") as Logger
    val appender = ListAppender<ILoggingEvent>().apply { start() }
    logger.addAppender(appender)
    try {
        block()
    } finally {
        logger.detachAppender(appender)
    }
    return appender.list.map { event ->
        Json.parseToJsonElement(encoder.encode(event).decodeToString()).jsonObject
    }
}

class RequestLogTests {
    @Test
    fun `each request is one JSON event with its fields at the top level`() {
        lateinit var requestId: String
        val events = captureRequestLog {
            withTestApp {
                requestId = client.get("/api/tags/not-a-uuid").read<ApiError>().requestId
            }
        }

        val event = events.single()
        assertEquals("WARN", event["level"]?.jsonPrimitive?.content)
        assertEquals("GET", event["method"]?.jsonPrimitive?.content)
        assertEquals("/api/tags/not-a-uuid", event["path"]?.jsonPrimitive?.content)
        assertEquals(404, event["status"]?.jsonPrimitive?.int)
        assertEquals(requestId, event["requestId"]?.jsonPrimitive?.content)
        assertEquals("test-user", event["user"]?.jsonPrimitive?.content)
        val entry = event["entries"]!!.jsonArray.single().jsonObject
        assertEquals("NotFound", entry["errorType"]?.jsonPrimitive?.content)
    }
}
