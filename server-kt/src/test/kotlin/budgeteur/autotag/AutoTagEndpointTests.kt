package budgeteur.autotag

import budgeteur.asUser
import budgeteur.feature.autotag.MatchesResponse
import budgeteur.feature.autotag.RunAutoTagResponse
import budgeteur.feature.transaction.TransactionResponse
import budgeteur.feature.transaction.TransactionTagResponse
import budgeteur.json
import budgeteur.read
import budgeteur.transaction.createTag
import budgeteur.transaction.createTransaction
import budgeteur.transaction.transaction
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

class AutoTagEndpointTests {
    private val other = "someone-else"

    private suspend fun HttpClient.createRule(pattern: String, tagId: UUID) {
        val response =
            post("/api/rules") {
                json("""{"pattern": "$pattern", "target": "Tag", "tagId": "$tagId"}""")
            }
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
    }

    private suspend fun HttpClient.run(
        action: String,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        post("/api/auto-tag") {
            json("""{"action": "$action"}""")
            configure()
        }

    private suspend fun HttpClient.ran(
        action: String,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): RunAutoTagResponse {
        val response = run(action, configure)
        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.tagOf(id: UUID, configure: HttpRequestBuilder.() -> Unit = {}) =
        get("/api/transactions/$id", configure).read<TransactionResponse>().tag

    @Test
    fun `TagUntagged gives a matching transaction a rule tag`() = withTestApp {
        val groceries = client.createTag("Groceries")
        client.createRule("COUNTDOWN", groceries)
        val id = client.createTransaction(transaction("PAY Countdown Ponsonby")).id

        assertEquals(RunAutoTagResponse(1, 0, 0), client.ran("TagUntagged"))
        assertEquals(TransactionTagResponse(groceries, "Rule"), client.tagOf(id))
    }

    @Test
    fun `a run leaves transfers untagged`() = withTestApp {
        client.createRule("SAVINGS", client.createTag("Savings"))
        val id = client.createTransaction(transaction("To savings", isTransfer = true)).id

        assertEquals(RunAutoTagResponse(0, 0, 0), client.ran("Retag"))
        assertEquals(null, client.tagOf(id))
    }

    @Test
    fun `a run reads and writes only the caller's data`() = withTestApp {
        client.createRule("COUNTDOWN", client.createTag("Groceries"))
        val theirs = client.createTransaction(transaction("Countdown")) { asUser(other) }.id

        assertEquals(RunAutoTagResponse(0, 0, 0), client.ran("Retag"), "the caller has none")
        assertEquals(
            RunAutoTagResponse(0, 0, 0),
            client.ran("Retag") { asUser(other) },
            "another user's rules do not apply",
        )
        assertEquals(null, client.tagOf(theirs) { asUser(other) })
    }

    @Test
    fun `matches counts the caller's transactions, not transfers`() = withTestApp {
        listOf(
                "2026-03-01" to "Countdown Ponsonby",
                "2026-03-03" to "Countdown Grey Lynn",
                "2026-03-02" to "Countdown Ponsonby",
                "2026-03-04" to "Rent",
            )
            .forEach { (date, description) ->
                client.createTransaction(transaction(description, date = date))
            }
        client.createTransaction(transaction("Countdown savings", isTransfer = true))
        client.createTransaction(transaction("Countdown")) { asUser(other) }

        val response = client.get("/api/auto-tag/matches?pattern=countdown")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(
            MatchesResponse(3, 4, listOf("Countdown Grey Lynn", "Countdown Ponsonby")),
            response.read<MatchesResponse>(),
        )
    }

    @Test
    fun `matches rejects a missing or blank pattern`() = withTestApp {
        listOf("", "?pattern=%20").forEach {
            assertEquals(
                HttpStatusCode.BadRequest,
                client.get("/api/auto-tag/matches$it").status,
                "'$it'",
            )
        }
    }

    @Test
    fun `an unknown action is a bad request`() = withTestApp {
        assertEquals(HttpStatusCode.BadRequest, client.run("TagEverything").status)
    }
}
