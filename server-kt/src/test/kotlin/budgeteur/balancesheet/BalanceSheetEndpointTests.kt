package budgeteur.balancesheet

import budgeteur.asUser
import budgeteur.feature.account.AccountResponse
import budgeteur.feature.balancesheet.BalanceSheetItemResponse
import budgeteur.feature.balancesheet.BalanceSheetResponse
import budgeteur.feature.balancesheet.ItemObservationResponse
import budgeteur.feature.balancesheet.LateTransactionsResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.transaction.createTransaction
import budgeteur.transaction.transaction
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BalanceSheetEndpointTests {
    /** The server's clock: 14 March in UTC, so the latest accepted date is 15 March. */
    private val clock = { Instant.parse("2026-03-14T12:00:00Z") }
    private val other = "someone-else"
    private val items = "/api/balance-sheet/items"

    private suspend fun HttpClient.create(
        name: String,
        side: String = "Asset",
        term: String = "Current",
        value: String = "100",
        asOf: String = "2026-03-01",
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        post(items) {
            json(
                """{"name": "$name", "side": "$side", "term": "$term", "value": "$value", """ +
                    """"asOf": "$asOf"}"""
            )
            configure()
        }

    private suspend fun HttpClient.created(
        name: String,
        side: String = "Asset",
        term: String = "Current",
        value: String = "100",
    ): BalanceSheetItemResponse {
        val response = create(name, side, term, value)
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.record(id: UUID, value: String, asOf: String) =
        post("$items/$id/observations") { json("""{"value": "$value", "asOf": "$asOf"}""") }

    private suspend fun HttpClient.sheet(configure: HttpRequestBuilder.() -> Unit = {}) =
        get("/api/balance-sheet", configure).read<BalanceSheetResponse>()

    private suspend fun HttpClient.account(name: String, balance: String?): UUID {
        val opening = balance?.let { """, "balance": {"balance": "$it", "asOf": "2026-03-01"}""" }
        val response =
            post("/api/accounts") {
                json("""{"name": "$name", "term": "Current"${opening.orEmpty()}}""")
            }
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
        return response.read<AccountResponse>().id
    }

    @Test
    fun `the sheet assembles and totals the items`() =
        withTestApp(clock) {
            val empty = client.sheet()
            assertEquals(emptyList(), empty.items)
            assertEquals("0.00", empty.netWorth)

            client.created("Chequing", "Asset", "Current", "2000")
            client.created("House", "Asset", "NonCurrent", "400000")
            client.created("Credit card", "Liability", "Current", "1500")
            client.created("Mortgage", "Liability", "NonCurrent", "300000")

            val sheet = client.sheet()
            assertEquals(
                listOf("Chequing", "Credit card", "House", "Mortgage"),
                sheet.items.map { it.name },
            )
            assertEquals("2000.00", sheet.totalCurrentAssets)
            assertEquals("400000.00", sheet.totalNonCurrentAssets)
            assertEquals("1500.00", sheet.totalCurrentLiabilities)
            assertEquals("300000.00", sheet.totalNonCurrentLiabilities)
            assertEquals("402000.00", sheet.totalAssets)
            assertEquals("301500.00", sheet.totalLiabilities)
            assertEquals("100500.00", sheet.netWorth)
            assertEquals("500.00", sheet.workingCapital)

            val body = client.get("/api/balance-sheet").bodyAsText()
            assertContains(body, """"totalAssets":"402000.00"""", message = "money is a string")
        }

    @Test
    fun `accounts are lines by the sign of their balance`() =
        withTestApp(clock) {
            client.created("House", "Asset", "NonCurrent", "1000")
            client.account("Everyday", "1000")
            client.account("Credit card", "-400")
            client.account("New card", null)

            val sheet = client.sheet()
            assertEquals(
                listOf("Credit card" to "Liability", "Everyday" to "Asset"),
                sheet.accounts.map { it.name to it.side },
            )
            assertEquals(listOf("400.00", "1000.00"), sheet.accounts.map { it.balance })
            assertEquals(listOf("New card"), sheet.unknownBalances.map { it.name })
            assertEquals("1600.00", sheet.netWorth, "the unknown balance adds nothing")
            assertEquals("600.00", sheet.workingCapital)

            val theirs = client.sheet { asUser(other) }
            assertEquals(emptyList(), theirs.accounts)
            assertEquals(emptyList(), theirs.unknownBalances)
            assertEquals(emptyList(), theirs.items)
        }

    @Test
    fun `an item is unique by name, side and term`() =
        withTestApp(clock) {
            val chequing = client.created("Chequing")

            val duplicate = client.create("Chequing", value = "999")
            assertEquals(HttpStatusCode.BadRequest, duplicate.status)
            assertEquals(
                "An identical balance sheet item already exists.",
                duplicate.read<ApiError>().details,
            )

            val savings = client.created("Chequing", term = "NonCurrent")
            assertEquals(
                HttpStatusCode.BadRequest,
                client
                    .put("$items/${savings.id}") {
                        json("""{"name": "Chequing", "term": "Current"}""")
                    }
                    .status,
                "an update onto another item's key",
            )
            assertEquals(
                HttpStatusCode.OK,
                client
                    .put("$items/${chequing.id}") {
                        json("""{"name": "Chequing", "term": "Current"}""")
                    }
                    .status,
                "an item keeps its own key",
            )
        }

    @Test
    fun `create reports every invalid field in one response`() =
        withTestApp(clock) {
            val response = client.create(" ", "Owned", "Fixed", "-1", "2026-03-16")

            assertEquals(HttpStatusCode.BadRequest, response.status)
            val lines = response.read<ApiError>().details.lines()
            assertEquals(5, lines.size, "one line per failure: $lines")
            assertTrue("2026-03-16 is in the future" in lines[4])
            assertEquals(emptyList(), client.sheet().items, "nothing was written")
        }

    @Test
    fun `an item's value is its latest observation`() =
        withTestApp(clock) {
            val house = client.created("House", term = "NonCurrent", value = "2000")
            assertEquals("2000.00" to "2026-03-01", house.value to house.asOf)

            val newer = client.record(house.id, "2100", "2026-03-05")
            assertEquals(HttpStatusCode.OK, newer.status)
            assertEquals("2100.00", newer.read<BalanceSheetItemResponse>().value)

            val older =
                client.record(house.id, "1900", "2026-02-01").read<BalanceSheetItemResponse>()
            assertEquals("2100.00", older.value, "an older value does not replace a newer one")

            val replaced =
                client.record(house.id, "2200", "2026-03-05").read<BalanceSheetItemResponse>()
            assertEquals("2200.00", replaced.value, "a value on the same date replaces it")

            val updated =
                client
                    .put("$items/${house.id}") {
                        json("""{"name": "Home", "term": "NonCurrent"}""")
                    }
                    .read<BalanceSheetItemResponse>()
            assertEquals("Home" to "2200.00", updated.name to updated.value)
            assertEquals("Asset", updated.side, "the side is fixed")

            assertEquals(
                HttpStatusCode.BadRequest,
                client.record(house.id, "-1", "2026-03-06").status,
            )
            assertEquals(
                HttpStatusCode.BadRequest,
                client.record(house.id, "1", "2026-03-16").status,
                "a value dated after tomorrow",
            )
            val theirs =
                client.post("$items/${house.id}/observations") {
                    json("""{"value": "1", "asOf": "2026-03-06"}""")
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, theirs.status)
            assertEquals(
                "2200.00",
                client.get("$items/${house.id}").read<BalanceSheetItemResponse>().value,
            )
        }

    @Test
    fun `an item's values are listed and deleted, but never its last`() =
        withTestApp(clock) {
            val house = client.created("House")
            client.record(house.id, "200", "2026-03-05")
            val path = "$items/${house.id}/observations"

            assertEquals(
                listOf(
                    ItemObservationResponse("200.00", "2026-03-05"),
                    ItemObservationResponse("100.00", "2026-03-01"),
                ),
                client.get(path).read<List<ItemObservationResponse>>(),
            )
            assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
            assertEquals(
                HttpStatusCode.NotFound,
                client.delete("$path/2026-03-05") { asUser(other) }.status,
            )

            assertEquals(HttpStatusCode.NoContent, client.delete("$path/2026-03-05").status)
            assertEquals(
                "100.00",
                client.get("$items/${house.id}").read<BalanceSheetItemResponse>().value,
            )
            assertEquals(HttpStatusCode.NotFound, client.delete("$path/2026-03-05").status)
            assertEquals(HttpStatusCode.BadRequest, client.delete("$path/01-03-2026").status)

            val last = client.delete("$path/2026-03-01")
            assertEquals(HttpStatusCode.BadRequest, last.status)
            assertContains(last.read<ApiError>().details, "only value")
        }

    @Test
    fun `another user cannot see, change, or delete an item`() =
        withTestApp(clock) {
            val house = client.created("House")
            val path = "$items/${house.id}"

            assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
            val hijack =
                client.put(path) {
                    json("""{"name": "Mine", "term": "Current"}""")
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, hijack.status)
            val close =
                client.put("$path/close-date") {
                    json("""{"closedOn": "2026-03-10"}""")
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, close.status)
            assertEquals(
                HttpStatusCode.NotFound,
                client.delete("$path/close-date") { asUser(other) }.status,
            )
            assertEquals(HttpStatusCode.NotFound, client.delete(path) { asUser(other) }.status)

            assertEquals(house, client.get(path).read<BalanceSheetItemResponse>())
            assertEquals(HttpStatusCode.NoContent, client.delete(path).status)
            assertEquals(HttpStatusCode.NotFound, client.delete(path).status)
            assertEquals(emptyList(), client.sheet().items)
        }

    @Test
    fun `closed lines leave the sheet and are listed apart`() =
        withTestApp(clock) {
            val house = client.created("House", term = "NonCurrent", value = "400000")
            client.created("Car", value = "9000")
            val card = client.account("Credit card", "-400")
            listOf("2026-03-10", "2026-03-11", "2026-03-13").forEach {
                client.createTransaction(transaction(it, date = it, accountId = card))
            }

            assertEquals(
                HttpStatusCode.BadRequest,
                client
                    .put("$items/${house.id}/close-date") { json("""{"closedOn": "2026-03-16"}""") }
                    .status,
                "an item cannot be closed in advance",
            )
            val sold =
                client
                    .put("$items/${house.id}/close-date") { json("""{"closedOn": "2026-03-10"}""") }
                    .read<BalanceSheetItemResponse>()
            assertEquals("2026-03-10", sold.closedOn)
            client.put("/api/accounts/$card/close-date") { json("""{"closedOn": "2026-03-10"}""") }
            client.put("$items/${house.id}") { json("""{"name": "House", "term": "NonCurrent"}""") }

            val sheet = client.sheet()
            assertEquals(listOf("Car"), sheet.items.map { it.name })
            assertEquals(emptyList(), sheet.accounts)
            assertEquals("9000.00", sheet.netWorth)
            assertEquals(
                listOf("House" to "2026-03-10"),
                sheet.closedItems.map { it.name to it.closedOn },
                "editing kept the item closed",
            )
            val closed = sheet.closedAccounts.single()
            assertEquals("2026-03-10", closed.closedOn)
            assertEquals(
                LateTransactionsResponse(2, "2026-03-13"),
                closed.transactionsAfterClose,
                "transactions on the close date are the account's last",
            )

            assertEquals(
                HttpStatusCode.NoContent,
                client.delete("$items/${house.id}/close-date").status,
            )
            client.delete("/api/accounts/$card/close-date")
            val reopened = client.sheet()
            assertEquals("408600.00", reopened.netWorth)
            assertEquals(emptyList(), reopened.closedItems)
            assertEquals(emptyList(), reopened.closedAccounts)
        }
}
