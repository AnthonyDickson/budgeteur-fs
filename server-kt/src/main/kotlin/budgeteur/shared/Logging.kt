package budgeteur.shared

import ch.qos.logback.classic.LoggerContext
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.rolling.FixedWindowRollingPolicy
import ch.qos.logback.core.rolling.RollingFileAppender
import ch.qos.logback.core.rolling.SizeBasedTriggeringPolicy
import ch.qos.logback.core.util.Duration
import ch.qos.logback.core.util.FileSize
import java.nio.file.Path
import net.logstash.logback.encoder.LogstashEncoder
import org.slf4j.Logger
import org.slf4j.LoggerFactory

/**
 * The log's format: one JSON object per line, timestamps in UTC, as the F# server's Serilog compact
 * JSON. Key-value pairs (the request log's fields) become fields of the object. The console uses it
 * through `logback.xml`, the file through [logToFile].
 */
class JsonLogEncoder : LogstashEncoder() {
    init {
        setTimeZone("UTC")
        fieldNames.version = IGNORE
        fieldNames.levelValue = IGNORE
    }

    private companion object {
        const val IGNORE = "[ignore]"
    }
}

/** Where the file rolls over, as in the F# server. */
val LOG_FILE_SIZE: FileSize = FileSize.valueOf("10MB")

/** The files kept, the current one included, which bounds the log at about 100 MB. */
const val LOG_FILES_KEPT = 10

/**
 * Logs to [path] as well as the console, rolling it to `<path>.1`, `<path>.2` and so on when it
 * reaches [maxFileSize], and keeping [filesKept] files. Returns the appender, so a caller can stop
 * it.
 */
fun logToFile(
    path: Path,
    maxFileSize: FileSize = LOG_FILE_SIZE,
    filesKept: Int = LOG_FILES_KEPT,
): RollingFileAppender<ILoggingEvent> {
    val context = LoggerFactory.getILoggerFactory() as LoggerContext
    val appender = RollingFileAppender<ILoggingEvent>()
    appender.context = context
    appender.name = "FILE"
    appender.file = path.toString()
    appender.encoder = JsonLogEncoder().apply { this.context = context }

    appender.rollingPolicy =
        FixedWindowRollingPolicy().apply {
            this.context = context
            setParent(appender)
            fileNamePattern = "$path.%i"
            minIndex = 1
            maxIndex = filesKept - 1
        }
    appender.triggeringPolicy =
        SizeBasedTriggeringPolicy<ILoggingEvent>().apply {
            this.context = context
            this.maxFileSize = maxFileSize
            // Logback checks the size at most once a minute by default, so a burst could
            // overshoot it by far.
            checkIncrement = Duration.buildBySeconds(1.0)
        }

    appender.encoder.start()
    appender.rollingPolicy.start()
    appender.triggeringPolicy.start()
    appender.start()
    context.getLogger(Logger.ROOT_LOGGER_NAME).addAppender(appender)
    return appender
}
