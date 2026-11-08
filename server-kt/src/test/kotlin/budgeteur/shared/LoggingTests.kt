package budgeteur.shared

import ch.qos.logback.classic.Logger
import ch.qos.logback.core.util.FileSize
import java.nio.file.Files
import kotlin.io.path.ExperimentalPathApi
import kotlin.io.path.deleteRecursively
import kotlin.io.path.exists
import kotlin.io.path.readLines
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.slf4j.LoggerFactory

class LoggingTests {
    @OptIn(ExperimentalPathApi::class)
    @Test
    fun `the log file holds JSON lines, rolls at its size, and keeps its count`() {
        val dir = Files.createTempDirectory("budgeteur-logs-")
        val path = dir.resolve("app.log")
        val appender = logToFile(path, maxFileSize = FileSize.valueOf("1KB"), filesKept = 2)
        val log = LoggerFactory.getLogger("budgeteur.LoggingTests")
        try {
            log.info("first")
            val line = Json.parseToJsonElement(path.readLines().single()).jsonObject
            assertEquals("first", line["message"]?.jsonPrimitive?.content)

            // The size is checked at most once a second, so space the writes out. Each write
            // after a pause rolls the file, and with two files kept the second roll replaces
            // app.log.1.
            repeat(2) {
                log.info("x".repeat(2048))
                Thread.sleep(1100)
            }
            log.info("last")

            assertTrue(path.resolveSibling("app.log.1").exists(), "the file did not roll")
            assertFalse(path.resolveSibling("app.log.2").exists(), "it kept too many files")
        } finally {
            (LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME) as Logger).detachAppender(
                appender
            )
            appender.stop()
            dir.deleteRecursively()
        }
    }
}
