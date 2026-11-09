package budgeteur.quicktag

import budgeteur.asUser
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.feature.autotag.RunAutoTagResponse
import budgeteur.feature.quicktag.ApprovalResponse
import budgeteur.feature.quicktag.BATCH_SIZE
import budgeteur.feature.quicktag.QueueResponse
import budgeteur.feature.quicktag.QueuedTransactionResponse
import budgeteur.feature.quicktag.SuggestionCountResponse
import budgeteur.feature.quicktag.SuggestionResponse
import budgeteur.feature.rule.RuleResponse
import budgeteur.feature.transaction.TransactionResponse
import budgeteur.feature.transaction.TransactionTagResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.Db
import budgeteur.transaction.createTag
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
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class QuickTagEndpointTests {
    private val other = "other-user"

    private suspend fun HttpClient.createRule(
        pattern: String,
        target: String,
        tagId: UUID? = null,
    ): RuleResponse {
        val tag = tagId?.let { """, "tagId": "$it"""" }.orEmpty()
        val response =
            post("/api/rules") { json("""{"pattern": "$pattern", "target": "$target"$tag}""") }
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.create(
        description: String,
        date: String = "2026-10-01",
        isTransfer: Boolean = false,
        tagId: UUID? = null,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): UUID =
        createTransaction(
                transaction(description, "-42.50", date, isTransfer = isTransfer, tagId = tagId),
                configure,
            )
            .id

    private suspend fun HttpClient.quickTag(
        id: UUID,
        tagId: UUID,
        suggested: Boolean = false,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        put("/api/quick-tag/$id") {
            json("""{"tagId": "$tagId", "suggested": $suggested}""")
            configure()
        }

    private suspend fun HttpClient.dismiss(
        id: UUID,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse = delete("/api/quick-tag/$id", configure)

    private suspend fun HttpClient.markTransfer(
        id: UUID,
        suggested: Boolean = false,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        put("/api/quick-tag/$id/transfer") {
            json("""{"suggested": $suggested}""")
            configure()
        }

    private suspend fun HttpClient.approve(
        target: String,
        tagId: UUID?,
        ids: List<UUID>,
    ): HttpResponse {
        val tag = tagId?.let { """"tagId": "$it", """ }.orEmpty()
        val list = ids.joinToString { "\"$it\"" }
        return post("/api/quick-tag/approvals") {
            json("""{"target": "$target", $tag"transactionIds": [$list]}""")
        }
    }

    private suspend fun HttpClient.queue(query: String = ""): QueueResponse {
        val response = get("/api/quick-tag$query")
        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.read(id: UUID) =
        get("/api/transactions/$id").read<TransactionResponse>()

    private suspend fun HttpClient.tagUntagged(): Int =
        post("/api/auto-tag") { json("""{"action": "TagUntagged"}""") }
            .read<RunAutoTagResponse>()
            .tagged

    /** The stored kind and source; a transfer's source is in no response. */
    private suspend fun Db.source(id: UUID): Pair<String?, String?>? = sql {
        select(CATEGORISATIONS.KIND, CATEGORISATIONS.SOURCE)
            .from(CATEGORISATIONS)
            .where(CATEGORISATIONS.TRANSACTION_ID.eq(id))
            .fetchOne { it.value1() to it.value2() }
    }

    @Test
    fun `quick tagging sets a manual tag, replacing a dismissal`() = withTestApp {
        val groceries = client.createTag("Groceries")
        val id = client.create("Countdown")

        assertEquals(HttpStatusCode.NoContent, client.quickTag(id, groceries).status)
        assertEquals(HttpStatusCode.NoContent, client.quickTag(id, groceries).status, "repeat")
        assertEquals(TransactionTagResponse(groceries, "Manual"), client.read(id).tag)

        assertEquals(HttpStatusCode.NoContent, client.dismiss(id).status)
        assertNull(client.read(id).tag, "a dismissed transaction has no tag")

        client.quickTag(id, groceries)
        assertEquals(TransactionTagResponse(groceries, "Manual"), client.read(id).tag)
    }

    @Test
    fun `rules never tag a dismissed transaction`() = withTestApp {
        client.createRule("COUNTDOWN", "Tag", client.createTag("Groceries"))
        val id = client.create("Countdown")

        assertEquals(HttpStatusCode.NoContent, client.dismiss(id).status)
        assertEquals(HttpStatusCode.NoContent, client.dismiss(id).status, "repeat")
        assertEquals(0, client.tagUntagged(), "tag untagged skips the dismissal")
        assertNull(client.read(id).tag)
    }

    @Test
    fun `another user's transaction is not found`() = withTestApp {
        client.createRule("COUNTDOWN", "Tag", client.createTag("Groceries"))
        val id = client.create("Countdown")
        val theirTag = client.createTag("Dining") { asUser(other) }

        assertEquals(
            HttpStatusCode.NotFound,
            client.quickTag(id, theirTag) { asUser(other) }.status,
        )
        assertEquals(HttpStatusCode.NotFound, client.dismiss(id) { asUser(other) }.status)
        assertEquals(HttpStatusCode.NotFound, client.markTransfer(id) { asUser(other) }.status)
        assertEquals(1, client.tagUntagged(), "the transaction is still untagged")
    }

    @Test
    fun `a tag the user does not have is rejected`() = withTestApp {
        val id = client.create("Countdown")
        val theirTag = client.createTag("Dining") { asUser(other) }

        assertEquals(HttpStatusCode.BadRequest, client.quickTag(id, theirTag).status)
        assertEquals(HttpStatusCode.BadRequest, client.quickTag(id, UUID.randomUUID()).status)
        assertNull(client.read(id).tag)
    }

    @Test
    fun `quick tagging a transfer replaces it`() = withTestApp {
        val groceries = client.createTag("Groceries")
        val id = client.create("Countdown", isTransfer = true)

        assertEquals(HttpStatusCode.NoContent, client.quickTag(id, groceries).status)
        val transaction = client.read(id)
        assertEquals(false, transaction.isTransfer)
        assertEquals(TransactionTagResponse(groceries, "Manual"), transaction.tag)
    }

    @Test
    fun `marking a transfer takes a transaction out of the queue`() = withTestApp {
        val id = client.create("To savings", tagId = client.createTag("Groceries"))

        assertEquals(HttpStatusCode.NoContent, client.markTransfer(id).status)
        assertEquals(HttpStatusCode.NoContent, client.markTransfer(id).status, "repeat")
        val transaction = client.read(id)
        assertTrue(transaction.isTransfer)
        assertNull(transaction.tag, "the tag is replaced")

        client.dismiss(id)
        assertTrue(client.queue().transactions.isEmpty(), "a dismissal leaves the queue")
        client.markTransfer(id)
        assertEquals(0, client.queue().total, "a transfer is not in the queue")
    }

    @Test
    fun `the queue is the user's untagged transactions, newest first`() = withTestApp {
        val older = client.create("Older", "2026-09-01")
        val newer = client.create("Newer", "2026-10-02")
        // Same date as the next: the later id comes first.
        val first = client.create("First", "2026-10-01")
        val second = client.create("Second", "2026-10-01")
        client.create("Tagged", tagId = client.createTag("Groceries"))
        client.dismiss(client.create("Dismissed"))
        client.create("Transfer", isTransfer = true)
        client.create("Another user's") { asUser(other) }

        val queue = client.queue()

        assertEquals(listOf(newer, second, first, older), queue.transactions.map { it.id })
        assertEquals(4, queue.total)
        assertEquals(
            QueuedTransactionResponse(newer, "-42.50", "Newer", "2026-10-02", null, null),
            queue.transactions.first(),
        )
    }

    @Test
    fun `a batch holds 50, and the next fetch continues the queue`() = withTestApp {
        val ids =
            (1L..51L).map {
                client.create("Transaction $it", LocalDate.of(2026, 1, 1).plusDays(it).toString())
            }

        val queue = client.queue()
        assertEquals(BATCH_SIZE, queue.transactions.size)
        assertEquals(51, queue.total)
        assertTrue(queue.transactions.none { it.id == ids.first() }, "the oldest waits")

        queue.transactions.forEach { client.dismiss(it.id) }

        val next = client.queue()
        assertEquals(listOf(ids.first()), next.transactions.map { it.id })
        assertEquals(1, next.total)
    }

    @Test
    fun `the queue suggests from the current rules, counts, and filters`() = withTestApp {
        val groceries = client.createTag("Groceries")
        client.createRule("COUNTDOWN", "Tag", groceries)
        val savings = client.createRule("TO SAVINGS", "Transfer")
        client.createRule("ASB CARD", "Transfer")
        listOf("Transfer to savings", "ASB CARD 1234", "Countdown", "Rent").forEach {
            client.create(it)
        }

        val queue = client.queue()

        assertEquals(
            listOf(
                "Rent" to null,
                "Countdown" to "COUNTDOWN",
                "ASB CARD 1234" to "ASB CARD",
                "Transfer to savings" to "TO SAVINGS",
            ),
            queue.transactions.map { it.description to it.suggestion?.pattern },
        )
        assertEquals(
            listOf(
                SuggestionCountResponse("Tag", groceries, 1),
                SuggestionCountResponse("Transfer", null, 2),
            ),
            queue.suggestions,
            "both transfer rules' suggestions are counted together",
        )

        val filtered = client.queue("?target=Transfer")
        assertEquals(
            listOf("ASB CARD 1234", "Transfer to savings"),
            filtered.transactions.map { it.description },
        )
        assertEquals(2, filtered.total)

        // Editing a rule changes its suggestions without a run.
        client.put("/api/rules/${savings.id}") {
            json("""{"pattern": "TO SAVINGS", "target": "Tag", "tagId": "$groceries"}""")
        }
        assertEquals(
            SuggestionResponse("Tag", groceries, "TO SAVINGS"),
            client
                .queue()
                .transactions
                .first { it.description == "Transfer to savings" }
                .suggestion,
        )
    }

    @Test
    fun `the queue filter is validated as for rules`() = withTestApp {
        val groceries = client.createTag("Groceries")
        listOf(
                "target=Tag",
                "target=Transfer&tagId=$groceries",
                "tagId=$groceries",
                "target=Tag&tagId=not-a-guid",
                "target=Dismissed",
            )
            .forEach {
                assertEquals(
                    HttpStatusCode.BadRequest,
                    client.get("/api/quick-tag?$it").status,
                    "'$it'",
                )
            }
    }

    @Test
    fun `a choice flagged as the suggestion is accepted`() = withTestApp { db ->
        val groceries = client.createTag("Groceries")
        val tagged = client.create("Countdown")
        val transfer = client.create("To savings")

        client.quickTag(tagged, groceries, suggested = true)
        client.markTransfer(transfer, suggested = true)
        assertEquals("Tagged" to "Accepted", db.source(tagged))
        assertEquals("Transfer" to "Accepted", db.source(transfer))

        client.quickTag(tagged, groceries)
        client.markTransfer(transfer)
        assertEquals("Tagged" to "Manual", db.source(tagged))
        assertEquals("Transfer" to "Manual", db.source(transfer))
    }

    @Test
    fun `marking a transfer needs the suggestion flag`() = withTestApp { db ->
        val id = client.create("To savings")

        val response = client.put("/api/quick-tag/$id/transfer") { json("{}") }

        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertNull(db.source(id))
    }

    @Test
    fun `approval accepts the listed transactions still queued`() = withTestApp { db ->
        val groceries = client.createTag("Groceries")
        val (first, second, tagged, unlisted) = (1..4).map { client.create("To savings $it") }
        // Tagged in another tab since the queue was read.
        client.quickTag(tagged, groceries)

        val response = client.approve("Transfer", null, listOf(first, second, tagged))

        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        assertEquals(ApprovalResponse(2), response.read<ApprovalResponse>())
        listOf(first, second).forEach { assertEquals("Transfer" to "Accepted", db.source(it)) }
        assertEquals("Tagged" to "Manual", db.source(tagged), "no longer queued, so skipped")
        assertNull(db.source(unlisted))

        assertEquals(
            ApprovalResponse(1),
            client.approve("Tag", groceries, listOf(unlisted)).read<ApprovalResponse>(),
        )
        assertEquals("Tagged" to "Accepted", db.source(unlisted))
        assertEquals(
            ApprovalResponse(0),
            client.approve("Transfer", null, listOf()).read<ApprovalResponse>(),
        )
    }

    @Test
    fun `approval rejects ids and tags the user does not have`() = withTestApp { db ->
        val id = client.create("To savings")
        val theirs = client.create("Another user's") { asUser(other) }
        val theirTag = client.createTag("Dining") { asUser(other) }

        assertEquals(
            HttpStatusCode.NotFound,
            client.approve("Transfer", null, listOf(id, theirs)).status,
        )
        assertNull(db.source(id), "nothing is written when one id is not found")
        assertEquals(
            HttpStatusCode.BadRequest,
            client.approve("Tag", theirTag, listOf(id)).status,
        )
        assertEquals(HttpStatusCode.BadRequest, client.approve("Tag", null, listOf(id)).status)
        assertEquals(
            HttpStatusCode.BadRequest,
            client.approve("Transfer", null, List(BATCH_SIZE + 1) { UUID.randomUUID() }).status,
            "more than a batch",
        )
    }
}
