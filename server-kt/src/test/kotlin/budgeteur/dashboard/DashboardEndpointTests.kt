package budgeteur.dashboard

import budgeteur.asUser
import budgeteur.feature.dashboard.DashboardResponse
import budgeteur.feature.dashboard.FigureResponse
import budgeteur.json
import budgeteur.read
import budgeteur.transaction.createTag
import budgeteur.transaction.createTransaction
import budgeteur.transaction.transaction
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// The figures are covered by the domain tests. These cover what only the endpoint can get wrong:
// the query, loading, scoping, and encoding.
class DashboardEndpointTests {
    /** The server's clock: 14 October 2026, after every date the tests use. */
    private val clock = { Instant.parse("2026-10-14T00:00:00Z") }

    private suspend fun HttpClient.spend(
        date: String,
        amount: String,
        tagId: UUID? = null,
        isTransfer: Boolean = false,
    ): UUID =
        createTransaction(
                transaction("Transaction", amount, date, isTransfer = isTransfer, tagId = tagId)
            )
            .id

    private suspend fun HttpClient.dashboard(
        configure: HttpRequestBuilder.() -> Unit = {}
    ): DashboardResponse {
        val response = get("/api/dashboard?today=2026-10-14", configure)
        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        return response.read()
    }

    @Test
    fun `the dashboard is read from the user's data`() =
        withTestApp(clock) {
            client.post("/api/balance-sheet/items") {
                json(
                    """{"name": "House", "side": "Asset", "term": "NonCurrent", "value": "400000", """ +
                        """"asOf": "2026-08-10"}"""
                )
            }
            client.spend("2026-09-01", "-1000")
            client.spend("2026-10-05", "-400")

            val response = client.get("/api/dashboard?today=2026-10-14")
            assertContains(
                response.bodyAsText(),
                "\"netWorth\":\"400000.00\"",
                message = "a string",
            )
            val dashboard = response.read<DashboardResponse>()

            assertEquals("October 2026", dashboard.month.label)
            assertEquals(
                FigureResponse("400.00", "1000.00", "-600.00", "-60.00"),
                dashboard.month.expenses,
                "October's expenses against September's",
            )
            assertEquals("2026-10-05", dashboard.month.latestTransaction)
            assertEquals(
                listOf("August 2026", "September 2026", "October 2026"),
                dashboard.history.map { it.label },
                "the history starts at the house's value",
            )
            assertEquals("1000.00", dashboard.totals?.averageExpenses, "September is the baseline")
            assertEquals("2026-08-10", dashboard.position.oldestAsOf)

            val theirs = client.dashboard { asUser("other-user") }
            assertTrue(theirs.position.isEmpty)
            assertTrue(theirs.month.expenseLines.isEmpty())
            assertNull(theirs.totals)
            assertEquals(listOf("October 2026"), theirs.history.map { it.label })
        }

    @Test
    fun `each transaction is joined to its tag and kind`() =
        withTestApp(clock) {
            val salary = client.createTag("Salary", "Income")
            val rent = client.createTag("Rent")
            client.spend("2026-10-10", "5000", salary)
            client.spend("2026-10-10", "-2000", rent)
            client.spend("2026-10-10", "-25")

            val month = client.dashboard().month

            assertEquals(
                listOf(Triple(salary, "Salary", "5000.00")),
                month.incomeLines.map { Triple(it.tagId, it.name, it.amount) },
            )
            assertEquals(
                listOf(Triple(rent, "Rent", "2000.00"), Triple(null, "Untagged expenses", "25.00")),
                month.expenseLines.map { Triple(it.tagId, it.name, it.amount) },
            )
        }

    @Test
    fun `a dismissed transaction counts as untagged`() =
        withTestApp(clock) {
            val id = client.spend("2026-10-10", "-25")
            assertEquals(HttpStatusCode.NoContent, client.delete("/api/quick-tag/$id").status)

            assertEquals(
                listOf("Untagged expenses" to "25.00"),
                client.dashboard().month.expenseLines.map { it.name to it.amount },
            )
        }

    @Test
    fun `transfers and transactions after today are excluded`() =
        withTestApp(clock) {
            client.spend("2026-10-01", "-100")
            client.spend("2026-10-14", "-10")
            client.spend("2026-10-05", "-999", isTransfer = true)
            client.spend("2026-10-05", "999", isTransfer = true)
            client.spend("2026-10-15", "-1000")

            val month = client.dashboard().month

            assertEquals("110.00", month.expenses.amount, "the first of the month and today count")
            assertEquals("0.00", month.income.amount, "the transfer in is not income")
        }

    @Test
    fun `a missing or malformed today is rejected`() =
        withTestApp(clock) {
            assertEquals(HttpStatusCode.BadRequest, client.get("/api/dashboard").status)
            val malformed = client.get("/api/dashboard?today=14/10/2026")
            assertEquals(HttpStatusCode.BadRequest, malformed.status)
            assertContains(malformed.bodyAsText(), "'today'")
        }
}
