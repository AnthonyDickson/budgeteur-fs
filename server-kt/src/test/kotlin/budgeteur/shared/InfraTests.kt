package budgeteur.shared

import budgeteur.feature.status.GetStatus
import budgeteur.read
import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InfraTests {
    @Test
    fun `migrations are journalled under DbUp's names and run once`() {
        val db = Db("jdbc:sqlite:file:test-${UUID.randomUUID()}?mode=memory&cache=shared")
        db.open().use { keeper ->
            val first = Migrations.run(db)
            assertTrue(first.isNotEmpty())
            assertEquals(emptyList(), Migrations.run(db))

            val names = keeper.query("SELECT ScriptName FROM SchemaVersions ORDER BY SchemaVersionID") { it.getString(1) }
            assertEquals(first.map { "Budgeteur.Data.Migrations.$it" }, names)
        }
    }

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
