package budgeteur.rule

import budgeteur.asUser
import budgeteur.feature.rule.RuleResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.transaction.createTag
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
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RuleEndpointTests {
    private val other = "someone-else"

    private fun body(pattern: String, target: String = "Tag", tagId: UUID? = null) =
        """{"pattern": "$pattern", "target": "$target", "tagId": ${tagId?.let { "\"$it\"" }}}"""

    private suspend fun HttpClient.create(
        pattern: String,
        tagId: UUID?,
        target: String = if (tagId == null) "Transfer" else "Tag",
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        post("/api/rules") {
            json(body(pattern, target, tagId))
            configure()
        }

    private suspend fun HttpClient.created(pattern: String, tagId: UUID?): RuleResponse {
        val response = create(pattern, tagId)
        assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
        return response.read()
    }

    @Test
    fun `a rule is created, read, replaced and deleted`() = withTestApp {
        val coffee = client.createTag("Coffee")
        val dining = client.createTag("Dining")
        val rule = client.created(" STARBUCKS ", coffee)
        assertEquals(RuleResponse(rule.id, "STARBUCKS", "Tag", coffee), rule)
        assertEquals(rule, client.get("/api/rules/${rule.id}").read<RuleResponse>())

        val moved =
            client
                .put("/api/rules/${rule.id}") { json(body("Starbucks", tagId = dining)) }
                .read<RuleResponse>()
        assertEquals(RuleResponse(rule.id, "Starbucks", "Tag", dining), moved)
        assertEquals(listOf(moved), client.get("/api/rules").read<List<RuleResponse>>())

        assertEquals(HttpStatusCode.NoContent, client.delete("/api/rules/${rule.id}").status)
        assertEquals(HttpStatusCode.NotFound, client.get("/api/rules/${rule.id}").status)
        assertEquals(HttpStatusCode.NotFound, client.delete("/api/rules/${rule.id}").status)
    }

    @Test
    fun `a rule is scoped to the owning user`() = withTestApp {
        val created = client.created("STARBUCKS", client.createTag("Coffee"))
        val path = "/api/rules/${created.id}"
        // A body that is valid for the other user, so only the rule's owner decides the outcome.
        val theirTag = client.createTag("Coffee") { asUser(other) }

        assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
        val hijack =
            client.put(path) {
                json(body("HIJACKED", tagId = theirTag))
                asUser(other)
            }
        assertEquals(HttpStatusCode.NotFound, hijack.status)
        assertEquals(HttpStatusCode.NotFound, client.delete(path) { asUser(other) }.status)
        assertEquals(
            emptyList(),
            client.get("/api/rules") { asUser(other) }.read<List<RuleResponse>>(),
        )
        assertEquals(created, client.get(path).read<RuleResponse>())
    }

    @Test
    fun `a pattern is unique per user, ignoring case, whatever its target`() = withTestApp {
        val coffee = client.createTag("Coffee")
        val dining = client.createTag("Dining")
        client.created("STARBUCKS", coffee)
        client.created("CAFÉ", coffee)

        // NOCASE in the schema folds ASCII only, so "café" checks that the server compares them.
        listOf("starbucks", "café").forEach {
            val duplicate = client.create(it, dining)
            assertEquals(HttpStatusCode.BadRequest, duplicate.status, it)
            assertTrue("already exists" in duplicate.read<ApiError>().details)
        }
        assertEquals(HttpStatusCode.BadRequest, client.create("Café", null).status)

        val theirTag = client.createTag("Coffee") { asUser(other) }
        assertEquals(
            HttpStatusCode.Created,
            client.create("STARBUCKS", theirTag) { asUser(other) }.status,
            "another user's pattern does not collide",
        )
    }

    @Test
    fun `an update may keep its own pattern but not take another's`() = withTestApp {
        val coffee = client.createTag("Coffee")
        client.created("STARBUCKS", coffee)
        val muffin = client.created("MUFFIN BREAK", coffee)
        val path = "/api/rules/${muffin.id}"

        assertEquals(
            HttpStatusCode.OK,
            client.put(path) { json(body("Muffin Break", tagId = coffee)) }.status,
        )
        assertEquals(
            HttpStatusCode.BadRequest,
            client.put(path) { json(body("Starbucks", tagId = coffee)) }.status,
        )
    }

    @Test
    fun `a rule cannot use another user's tag`() = withTestApp {
        val coffee = client.createTag("Coffee")
        assertEquals(
            HttpStatusCode.BadRequest,
            client.create("STARBUCKS", coffee) { asUser(other) }.status,
        )
    }

    @Test
    fun `a tag rule needs a tag and a transfer rule rejects one`() = withTestApp {
        val coffee = client.createTag("Coffee")
        listOf(
                Triple("Tag", null, "a tag rule without a tag"),
                Triple("Transfer", coffee, "a transfer rule with a tag"),
                Triple("Dismissed", null, "an unknown target"),
            )
            .forEach { (target, tagId, label) ->
                assertEquals(
                    HttpStatusCode.BadRequest,
                    client.create("STARBUCKS", tagId, target).status,
                    label,
                )
            }

        val response = client.create(" ", coffee, "Transfer")
        assertEquals(2, response.read<ApiError>().details.lines().size, "every failure is reported")

        val transfer = client.created("TO SAVINGS", null)
        assertEquals("Transfer" to null, transfer.target to transfer.tagId)
    }

    @Test
    fun `deleting a tag deletes its rules but not transfer rules`() = withTestApp {
        val coffee = client.createTag("Coffee")
        client.created("STARBUCKS", coffee)
        client.created("TO SAVINGS", null)

        client.delete("/api/tags/$coffee")

        assertEquals(
            listOf("TO SAVINGS"),
            client.get("/api/rules").read<List<RuleResponse>>().map { it.pattern },
        )
    }
}
