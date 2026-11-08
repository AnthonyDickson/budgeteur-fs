package budgeteur.shared

import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.server.application.ApplicationStopPreparing
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

class GracefulShutdownTests {
    @Test
    fun `a stop waits for the calls in flight`() = withTestApp {
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        routing {
            get("/test/slow") {
                started.complete(Unit)
                release.await()
                call.respondText("done")
            }
        }

        coroutineScope {
            val response = async { client.get("/test/slow") }
            started.await()
            // Ktor raises this on the thread that stops the server, and blocks on it.
            val stop =
                async(Dispatchers.IO) {
                    application.monitor.raise(ApplicationStopPreparing, application.environment)
                }
            delay(200)
            assertFalse(stop.isCompleted, "the stop went ahead with a call in flight")

            release.complete(Unit)
            assertEquals("done", response.await().bodyAsText())
            stop.await()
        }
    }
}
