package budgeteur.report

import budgeteur.asUser
import budgeteur.feature.balancesheet.BalanceSheetItemResponse
import budgeteur.feature.report.ReportResponse
import budgeteur.json
import budgeteur.read
import budgeteur.transaction.createTransaction
import budgeteur.transaction.transaction
import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// The figures are covered by ReportTests. These cover what only the endpoint can get wrong: the
// query, loading, scoping, and encoding.
class ReportEndpointTests {
    /** The server's clock: 14 October 2026, after every date the tests use. */
    private val clock = { Instant.parse("2026-10-14T00:00:00Z") }

    private val march = "/api/reports?frequency=Monthly&today=2026-10-14&date=2026-03-10"

    @Test
    fun `a report is read from the user's data`() =
        withTestApp(clock) {
            val house =
                client
                    .post("/api/balance-sheet/items") {
                        json(
                            """{"name": "House", "side": "Asset", "term": "NonCurrent", """ +
                                """"value": "400000", "asOf": "2026-01-10"}"""
                        )
                    }
                    .read<BalanceSheetItemResponse>()
            client.post("/api/balance-sheet/items/${house.id}/observations") {
                json("""{"value": "410000", "asOf": "2026-03-20"}""")
            }
            client.createTransaction(transaction("Rent", "-2000", "2026-03-05"))

            val response = client.get(march)
            assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
            assertContains(response.bodyAsText(), "\"changeInNetWorth\":\"10000.00\"")
            val report = response.read<ReportResponse>()

            assertEquals("March 2026", report.label)
            assertEquals("400000.00", report.opening.netWorth)
            assertEquals("410000.00", report.closing.netWorth)
            assertEquals("12000.00", report.otherChanges, "10k more net worth despite 2k spent")
            assertEquals("2000.00", report.expenses)
            assertTrue(report.hasPrevious && report.hasNext)

            val latest =
                client.get("/api/reports?frequency=Monthly&today=2026-10-14").read<ReportResponse>()
            assertEquals("September 2026", latest.label, "the latest complete period")

            assertEquals(
                HttpStatusCode.NotFound,
                client.get(march) { asUser("other-user") }.status,
                "another user has no data in March",
            )
        }

    @Test
    fun `invalid queries are reported together`() =
        withTestApp(clock) {
            val response = client.get("/api/reports?frequency=Weekly&date=x")

            assertEquals(HttpStatusCode.BadRequest, response.status)
            val body = response.bodyAsText()
            listOf("Weekly", "'today'", "'date'").forEach { assertContains(body, it) }
        }

    @Test
    fun `a period after today has no report`() =
        withTestApp(clock) {
            assertEquals(
                HttpStatusCode.NotFound,
                client
                    .get("/api/reports?frequency=Monthly&today=2026-10-14&date=2026-11-01")
                    .status,
            )
        }
}
