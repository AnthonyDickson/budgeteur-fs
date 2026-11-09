package budgeteur.account

import budgeteur.asUser
import budgeteur.feature.account.AccountBalanceResponse
import budgeteur.feature.account.AccountResponse
import budgeteur.feature.account.TransactionsAfterCloseResponse
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
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AccountEndpointTests {
    /** The server's clock: 14 March in UTC, so the latest accepted date is 15 March. */
    private val clock = { Instant.parse("2026-03-14T12:00:00Z") }
    private val other = "someone-else"

    private fun body(
        name: String,
        number: String? = null,
        term: String = "Current",
        balance: String? = null,
    ) =
        """{"name": "$name", "number": ${number?.let { "\"$it\"" }}, "term": "$term"""" +
            (balance?.let { """, "balance": $it""" } ?: "") +
            "}"

    private fun entry(balance: String, asOf: String) =
        """{"balance": "$balance", "asOf": "$asOf"}"""

    private suspend fun HttpClient.create(
        name: String,
        number: String? = null,
        balance: String? = null,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        post("/api/accounts") {
            json(body(name, number, balance = balance))
            configure()
        }

    private suspend fun HttpClient.created(
        name: String,
        number: String? = null,
        balance: String? = null,
    ): AccountResponse {
        val response = create(name, number, balance)
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.record(id: UUID, balance: String, asOf: String) =
        post("/api/accounts/$id/observations") { json(entry(balance, asOf)) }

    @Test
    fun `a created account is read back in canonical form, with its opening balance`() =
        withTestApp(clock) {
            val created =
                client.created(
                    " Everyday ",
                    "12 3456 789012 00",
                    balance = entry("1234.5", "2026-03-01"),
                )

            assertEquals("Everyday", created.name)
            assertEquals("12-3456-0789012-000", created.number)
            assertEquals(AccountBalanceResponse("1234.50", "2026-03-01"), created.balance)
            assertNull(created.closedOn)
            assertEquals(created, client.get("/api/accounts/${created.id}").read<AccountResponse>())

            val savings = client.created("Savings")
            assertNull(savings.balance, "no opening balance leaves it unknown")
            assertEquals(
                listOf("Everyday", "Savings"),
                client.get("/api/accounts").read<List<AccountResponse>>().map { it.name },
            )
        }

    @Test
    fun `create reports every invalid field in one response`() =
        withTestApp(clock) {
            val response =
                client.post("/api/accounts") {
                    json(body(" ", "Savings", "Fixed", entry("10", "2026-03-16")))
                }

            assertEquals(HttpStatusCode.BadRequest, response.status)
            val lines = response.read<ApiError>().details.lines()
            assertEquals(4, lines.size, "one line per failure: $lines")
            assertTrue(lines[0].startsWith("Account name cannot"))
            assertTrue("not an account number" in lines[1])
            assertTrue("Term" in lines[2])
            assertTrue("2026-03-16 is in the future" in lines[3])
        }

    @Test
    fun `a recorded balance is current unless an older one`() =
        withTestApp(clock) {
            val account = client.created("Everyday", balance = entry("100", "2026-03-01"))

            val newer = client.record(account.id, "200", "2026-03-05").read<AccountResponse>()
            assertEquals(AccountBalanceResponse("200.00", "2026-03-05"), newer.balance)

            val older = client.record(account.id, "50", "2026-02-01").read<AccountResponse>()
            assertEquals(AccountBalanceResponse("200.00", "2026-03-05"), older.balance)

            val replaced = client.record(account.id, "250", "2026-03-05").read<AccountResponse>()
            assertEquals(AccountBalanceResponse("250.00", "2026-03-05"), replaced.balance)

            assertEquals(
                HttpStatusCode.BadRequest,
                client.record(account.id, "1", "2026-03-16").status,
                "a balance cannot be dated in the future",
            )
        }

    @Test
    fun `an account's balances are listed newest first and deleted`() =
        withTestApp(clock) {
            val account = client.created("Everyday", balance = entry("100", "2026-03-01"))
            client.record(account.id, "200", "2026-03-05")
            val path = "/api/accounts/${account.id}/observations"

            assertEquals(
                listOf("2026-03-05", "2026-03-01"),
                client.get(path).read<List<AccountBalanceResponse>>().map { it.asOf },
            )

            assertEquals(HttpStatusCode.NoContent, client.delete("$path/2026-03-05").status)
            val current = client.get("/api/accounts/${account.id}").read<AccountResponse>()
            assertEquals(
                "2026-03-01",
                current.balance?.asOf,
                "the previous balance becomes current",
            )

            assertEquals(HttpStatusCode.NotFound, client.delete("$path/2026-03-05").status)
            assertEquals(HttpStatusCode.BadRequest, client.delete("$path/05-03-2026").status)

            client.delete("$path/2026-03-01")
            assertNull(client.get("/api/accounts/${account.id}").read<AccountResponse>().balance)
        }

    @Test
    fun `numbers are unique per user, whatever their form`() =
        withTestApp(clock) {
            val everyday = client.created("Everyday", "12-3456-0789012-00")

            val duplicate = client.create("Again", "12 3456 789012 000")
            assertEquals(HttpStatusCode.BadRequest, duplicate.status)
            assertEquals(
                "Another account already has the number 12-3456-0789012-000.",
                duplicate.read<ApiError>().details,
            )

            val renamed =
                client.put("/api/accounts/${everyday.id}") {
                    json(body("Renamed", "12-3456-0789012-00"))
                }
            assertEquals(HttpStatusCode.OK, renamed.status, "an account keeps its own number")

            assertEquals(
                HttpStatusCode.Created,
                client.create("Theirs", "12-3456-0789012-00") { asUser(other) }.status,
            )
        }

    @Test
    fun `another user cannot see, change, or delete an account`() =
        withTestApp(clock) {
            val account = client.created("Everyday", balance = entry("100", "2026-03-01"))
            val path = "/api/accounts/${account.id}"

            assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
            val hijack =
                client.put(path) {
                    json(body("Mine"))
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, hijack.status)
            assertEquals(HttpStatusCode.NotFound, client.delete(path) { asUser(other) }.status)
            val observations = client.get("$path/observations") { asUser(other) }
            assertEquals(HttpStatusCode.NotFound, observations.status)
            val record =
                client.post("$path/observations") {
                    json(entry("1", "2026-03-02"))
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, record.status)
            val close =
                client.put("$path/close-date") {
                    json("""{"closedOn": "2026-03-10"}""")
                    asUser(other)
                }
            assertEquals(HttpStatusCode.NotFound, close.status)
            assertEquals(
                emptyList(),
                client.get("/api/accounts") { asUser(other) }.read<List<AccountResponse>>(),
            )

            assertEquals(account, client.get(path).read<AccountResponse>())
        }

    @Test
    fun `an update replaces the details and keeps the balance and close date`() =
        withTestApp(clock) {
            val account = client.created("Everyday", balance = entry("100", "2026-03-01"))
            val path = "/api/accounts/${account.id}"
            client.put("$path/close-date") { json("""{"closedOn": "2026-03-10"}""") }

            val updated =
                client
                    .put(path) { json(body("Bills", "XXXX-XXXX-XXXX-1234", "NonCurrent")) }
                    .read<AccountResponse>()

            assertEquals(
                Triple("Bills", "XXXX-XXXX-XXXX-1234", "NonCurrent"),
                Triple(updated.name, updated.number, updated.term),
            )
            assertEquals(account.balance, updated.balance)
            assertEquals("2026-03-10", updated.closedOn)
        }

    @Test
    fun `closing flags later transactions and reopening clears the date`() =
        withTestApp(clock) {
            val account = client.created("Everyday")
            val path = "/api/accounts/${account.id}/close-date"
            listOf("2026-03-10", "2026-03-11", "2026-03-13").forEach {
                client.createTransaction(transaction(it, date = it, accountId = account.id))
            }

            assertEquals(
                HttpStatusCode.BadRequest,
                client.put(path) { json("""{"closedOn": "2026-03-16"}""") }.status,
                "an account cannot be closed in advance",
            )

            val closed =
                client.put(path) { json("""{"closedOn": "2026-03-10"}""") }.read<AccountResponse>()
            assertEquals("2026-03-10", closed.closedOn)
            assertEquals(
                TransactionsAfterCloseResponse(2, "2026-03-13"),
                closed.transactionsAfterClose,
                "transactions on the close date are the account's last",
            )

            assertEquals(HttpStatusCode.NoContent, client.delete(path).status)
            val reopened = client.get("/api/accounts/${account.id}").read<AccountResponse>()
            assertNull(reopened.closedOn)
            assertNull(reopened.transactionsAfterClose)
            assertEquals(HttpStatusCode.NoContent, client.delete(path).status, "already open")
        }

    @Test
    fun `deleting an account deletes its balances and transactions`() =
        withTestApp(clock) {
            val account = client.created("Everyday", balance = entry("100", "2026-03-01"))
            val kept = client.createTransaction(transaction("Cash"))
            val gone = client.createTransaction(transaction("Coffee", accountId = account.id))

            assertEquals(
                HttpStatusCode.NoContent,
                client.delete("/api/accounts/${account.id}").status,
            )

            assertEquals(HttpStatusCode.NotFound, client.get("/api/accounts/${account.id}").status)
            assertEquals(HttpStatusCode.NotFound, client.get("/api/transactions/${gone.id}").status)
            assertEquals(HttpStatusCode.OK, client.get("/api/transactions/${kept.id}").status)
        }
}
