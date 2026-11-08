package budgeteur.shared

import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCallPipeline
import io.ktor.server.application.ApplicationStopPreparing
import io.ktor.server.application.log
import java.util.concurrent.atomic.AtomicInteger
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/** How long a stop waits for in-flight calls, as the F# server's host does. */
val SHUTDOWN_TIMEOUT: Duration = 30.seconds

private val pollInterval = 20.milliseconds

/**
 * Holds a stop until the calls in flight finish, for at most [timeout], as ASP.NET Core's host
 * does. Ktor's own grace period is Netty's quiet period: the workers stop once they have been idle
 * that long, cutting off a call that is waiting on anything else, and every stop takes at least
 * that long.
 *
 * Ktor raises [ApplicationStopPreparing] before it closes the listening socket, so a call that
 * arrives while this waits is served and waited for too.
 */
fun Application.drainCallsOnStop(timeout: Duration) {
    val inFlight = AtomicInteger()

    intercept(ApplicationCallPipeline.Setup) {
        inFlight.incrementAndGet()
        try {
            proceed()
        } finally {
            inFlight.decrementAndGet()
        }
    }

    monitor.subscribe(ApplicationStopPreparing) {
        val deadline = TimeSource.Monotonic.markNow() + timeout
        while (inFlight.get() > 0 && deadline.hasNotPassedNow()) {
            Thread.sleep(pollInterval.inWholeMilliseconds)
        }
        val abandoned = inFlight.get()
        if (abandoned > 0) log.warn("Stopping with $abandoned calls still in flight after $timeout")
    }
}
