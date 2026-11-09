package budgeteur.transaction

import budgeteur.DEFAULT_TEST_USER
import budgeteur.asUser
import budgeteur.data.saveCategorisation
import budgeteur.domain.Categorisation
import budgeteur.feature.transaction.PAGE_SIZE
import budgeteur.feature.transaction.SearchAccountRequest
import budgeteur.feature.transaction.SearchAmountRequest
import budgeteur.feature.transaction.SearchCriteriaRequest
import budgeteur.feature.transaction.SearchDatesRequest
import budgeteur.feature.transaction.SearchRequest
import budgeteur.feature.transaction.SearchResponse
import budgeteur.feature.transaction.SearchTagRequest
import budgeteur.json
import budgeteur.read
import budgeteur.shared.apiJson
import budgeteur.shared.newId
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.post
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class SearchEndpointTests {
    private val anyCriteria =
        SearchCriteriaRequest(
            text = "",
            dates = SearchDatesRequest("AnyTime"),
            account = SearchAccountRequest("Any"),
            tag = SearchTagRequest("Any"),
            amount = SearchAmountRequest("Any"),
        )

    private fun amount(direction: String, minimum: String? = null, maximum: String? = null) =
        anyCriteria.copy(amount = SearchAmountRequest(direction, minimum, maximum))

    private suspend fun HttpClient.post(
        criteria: SearchCriteriaRequest,
        cursor: String? = null,
    ): HttpResponse =
        post("/api/transactions/search") {
            json(apiJson.encodeToString(SearchRequest(criteria, "2026-03-15", cursor)))
        }

    private suspend fun HttpClient.searchPage(
        criteria: SearchCriteriaRequest,
        cursor: String? = null,
    ): SearchResponse {
        val response = post(criteria, cursor)
        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        return response.read()
    }

    /** The first page's descriptions, in order. */
    private suspend fun HttpClient.search(criteria: SearchCriteriaRequest) =
        searchPage(criteria).transactions.map { it.description }

    /** The first page's descriptions, sorted, for matches on the same day. */
    private suspend fun HttpClient.searchSorted(criteria: SearchCriteriaRequest) =
        search(criteria).sorted()

    @Test
    fun `text matches descriptions ignoring case`() = withTestApp {
        listOf("COUNTDOWN AUCKLAND", "New World", "countdown metro").forEach {
            client.createTransaction(transaction(it))
        }

        assertEquals(
            listOf("countdown metro", "COUNTDOWN AUCKLAND"),
            client.search(anyCriteria.copy(text = "Countdown")),
            "matches, newest first",
        )
    }

    @Test
    fun `text matches only as text, not as a LIKE pattern`() = withTestApp {
        listOf("100% juice", "1000 juices", "a_b", "ab").forEach {
            client.createTransaction(transaction(it))
        }

        assertEquals(listOf("100% juice"), client.search(anyCriteria.copy(text = "0%")))
        assertEquals(listOf("a_b"), client.search(anyCriteria.copy(text = "_")))
    }

    @Test
    fun `dates match inclusive days and presets resolve`() = withTestApp {
        listOf("2026-01-31", "2026-02-01", "2026-02-28", "2026-03-01").forEach {
            client.createTransaction(transaction(it, date = it))
        }

        val custom =
            anyCriteria.copy(dates = SearchDatesRequest("Custom", "2026-02-01", "2026-02-28"))
        assertEquals(listOf("2026-02-28", "2026-02-01"), client.search(custom))

        val lastMonth = client.searchPage(anyCriteria.copy(dates = SearchDatesRequest("LastMonth")))
        assertEquals(
            listOf("2026-02-28", "2026-02-01"),
            lastMonth.transactions.map { it.description },
        )
        assertEquals("2026-02-01" to "2026-02-28", lastMonth.from to lastMonth.to)
    }

    @Test
    fun `account matches one account or none`() = withTestApp { db ->
        val everyday = db.insertAccount(DEFAULT_TEST_USER, "Everyday")
        val savings = db.insertAccount(DEFAULT_TEST_USER, "Savings")
        client.createTransaction(transaction("Everyday", accountId = everyday))
        client.createTransaction(transaction("Savings", accountId = savings))
        client.createTransaction(transaction("Cash"))

        val oneAccount = anyCriteria.copy(account = SearchAccountRequest("Account", savings))
        assertEquals(listOf("Savings"), client.search(oneAccount))
        val noAccount = anyCriteria.copy(account = SearchAccountRequest("NoAccount"))
        assertEquals(listOf("Cash"), client.search(noAccount))
    }

    @Test
    fun `tag matches a tag or a categorisation`() = withTestApp { db ->
        val groceries = client.createTag("Groceries")
        val fuel = client.createTag("Fuel")
        client.createTransaction(transaction("Groceries", tagId = groceries))
        client.createTransaction(transaction("Fuel", tagId = fuel))
        client.createTransaction(transaction("Untagged"))
        client.createTransaction(transaction("Transfer", isTransfer = true))
        // Dismissing is quick tagging's, which the PoC does not have yet.
        val dismissed = client.createTransaction(transaction("Dismissed")).id
        db.sql { saveCategorisation(DEFAULT_TEST_USER, dismissed, Categorisation.Dismissed) }

        suspend fun byTag(state: String, id: UUID? = null) =
            client.searchSorted(anyCriteria.copy(tag = SearchTagRequest(state, id)))

        assertEquals(listOf("Fuel"), byTag("Tag", fuel))
        assertEquals(listOf("Dismissed", "Untagged"), byTag("WithoutTag"))
        assertEquals(listOf("Untagged"), byTag("Untagged"))
        assertEquals(listOf("Dismissed"), byTag("Dismissed"))
        assertEquals(listOf("Transfer"), byTag("Transfer"))
        assertEquals(emptyList(), byTag("Tag", newId()), "an unknown tag matches nothing")
    }

    @Test
    fun `amount matches a direction and sizes`() = withTestApp {
        listOf("50", "-50", "-120", "0", "300", "-300", "12.34").forEach {
            client.createTransaction(transaction(it, amount = it))
        }

        suspend fun matching(direction: String, minimum: String? = null, maximum: String? = null) =
            client.searchSorted(amount(direction, minimum, maximum))

        assertEquals(listOf("-120", "-50"), matching("Debit", "50", "200"))
        assertEquals(listOf("12.34", "300", "50"), matching("Credit"))
        assertEquals(listOf("-120", "-300", "300"), matching("Any", minimum = "100"))
        assertEquals(listOf("-50", "0", "12.34", "50"), matching("Any", maximum = "50"))
        assertEquals(listOf("12.34"), matching("Credit", "12.34", "12.34"))
        assertEquals(emptyList(), matching("Debit", maximum = "0"), "zero is not a debit")
    }

    @Test
    fun `criteria combine with AND`() = withTestApp {
        client.createTransaction(transaction("COUNTDOWN", "-20"))
        client.createTransaction(transaction("COUNTDOWN REFUND", "20"))
        client.createTransaction(transaction("NEW WORLD", "-20"))

        assertEquals(
            listOf("COUNTDOWN"),
            client.search(amount("Debit").copy(text = "countdown")),
        )
    }

    @Test
    fun `only the caller's transactions match`() = withTestApp {
        client.createTransaction(transaction("Theirs")) { asUser("someone-else") }
        client.createTransaction(transaction("Mine"))

        assertEquals(listOf("Mine"), client.search(anyCriteria))
    }

    @Test
    fun `pages cover every match once across same-day ties`() = withTestApp {
        for (day in 1..3) {
            for (n in 1..50) client.createTransaction(
                transaction("$day-$n", date = "2026-03-0$day")
            )
        }

        val first = client.searchPage(anyCriteria)
        assertEquals(PAGE_SIZE, first.transactions.size, "a full first page")
        val cursor = assertNotNull(first.cursor, "a cursor after a full page")

        val second = client.searchPage(anyCriteria, cursor)
        assertEquals(50, second.transactions.size, "the rest")
        assertNull(second.cursor, "no cursor on the last page")

        val all = first.transactions + second.transactions
        assertEquals(150, all.map { it.id }.distinct().size, "every match once")
        val order = all.map { it.date to it.id.toString() }
        assertEquals(
            order.sortedWith(
                compareByDescending<Pair<String, String>> { it.first }
                    .thenByDescending { it.second }
            ),
            order,
            "newest first, then by id",
        )
    }

    @Test
    fun `invalid criteria and malformed cursors are 400`() = withTestApp {
        assertEquals(HttpStatusCode.BadRequest, client.post(amount("Any", "2", "1")).status)
        assertEquals(HttpStatusCode.BadRequest, client.post(anyCriteria, "nonsense").status)
    }
}
