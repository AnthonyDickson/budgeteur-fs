package budgeteur.shared

import budgeteur.feature.status.GetStatus
import budgeteur.data.db.tables.records.TagsRecord
import budgeteur.data.db.tables.references.TAGS
import budgeteur.read
import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import io.ktor.http.HttpStatusCode
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InfraTests {
    @Test
    fun `config reports every missing setting`() {
        val failures = Config.load(mapOf("PORT" to "nope")).leftOrNull().orEmpty()
        assertEquals(3, failures.size, failures.toString())
    }

    @Test
    fun `uuidV7 ids sort by creation time`() {
        val earlier = uuidV7(Instant.parse("2026-01-01T00:00:00Z"))
        val later = uuidV7(Instant.parse("2026-01-01T00:00:00.001Z"))
        assertEquals(7, earlier.version())
        assertEquals(2, earlier.variant())
        assertTrue(earlier.toString() < later.toString())
    }

    @Test
    fun `status reports a healthy database and the uptime from the clock`() {
        val start = Instant.parse("2026-01-01T00:00:00Z")
        var now = start
        withTestApp(clock = { now }) {
            now = start.plus(Duration.ofSeconds(90))
            val response = client.get(GetStatus.PATH)
            assertEquals(HttpStatusCode.OK, response.status)
            val status = response.read<GetStatus.StatusResponse>()
            assertEquals("healthy", status.database.status)
            assertEquals(90, status.uptimeSeconds)
            assertEquals("0h 1m 30s", status.uptime)
        }
    }
}

class EndpointTests {
    @Test
    fun `a constraint violation a handler did not check is a 409, not a 500`() =
        withTestApp { db ->
            routing {
                post("/test/duplicate") {
                    Endpoint.handle(call) {
                        val id = uuidV7()
                        db.sql { sql ->
                            repeat(2) {
                                sql.insertInto(TAGS).set(TagsRecord(id, "user", "Rent $it", "Red", "Expense")).execute()
                            }
                        }
                    }
                }
            }

            val response = client.post("/test/duplicate")
            assertEquals(HttpStatusCode.Conflict, response.status)
            assertEquals("Conflict", response.read<ApiError>().error)
        }
}
