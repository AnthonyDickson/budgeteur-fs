package budgeteur.tag

import budgeteur.asUser
import budgeteur.feature.tag.TagResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpStatusCode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TagEndpointTests {
    private fun body(name: String, color: String = "Green", kind: String = "Income") =
        """{"name": "$name", "color": "$color", "kind": "$kind"}"""

    private suspend fun HttpClient.create(name: String, kind: String = "Income"): HttpResponse =
        post("/api/tags") { json(body(name, kind = kind)) }

    @Test
    fun `the kind is stored on create and replaced on update`() =
        withTestApp {
            val created = client.create("Salary", kind = "Income")
            assertEquals(HttpStatusCode.Created, created.status)
            val tag = created.read<TagResponse>()
            assertEquals("Income", tag.kind)

            val updated = client.put("/api/tags/${tag.id}") { json(body("Salary", kind = "Expense")) }
            assertEquals(HttpStatusCode.OK, updated.status)

            val read = client.get("/api/tags/${tag.id}").read<TagResponse>()
            assertEquals("Expense", read.kind)
        }

    @Test
    fun `create reports every invalid field in one response`() =
        withTestApp {
            val response = client.post("/api/tags") { json(body("  ", color = "Beige", kind = "Asset")) }

            assertEquals(HttpStatusCode.BadRequest, response.status)
            val lines = response.read<ApiError>().details.lines()
            assertEquals(3, lines.size, "one line per failure: $lines")
            assertTrue(lines[0].startsWith("Tag name cannot"))
            assertTrue(lines[1].contains("TagColor"))
            assertTrue(lines[2].contains("TagKind"))
        }

    @Test
    fun `a malformed body is a validation error`() =
        withTestApp {
            val response = client.post("/api/tags") { json("""{"name": "Rent"}""") }
            assertEquals(HttpStatusCode.BadRequest, response.status)
        }

    @Test
    fun `names are unique per user, checked before the write`() =
        withTestApp {
            client.create("Rent")

            val duplicate = client.create(" Rent ")
            assertEquals(HttpStatusCode.BadRequest, duplicate.status)
            assertEquals("A tag with the name 'Rent' already exists", duplicate.read<ApiError>().details)

            val otherUser = client.post("/api/tags") { json(body("Rent")); asUser("someone-else") }
            assertEquals(HttpStatusCode.Created, otherUser.status)
        }

    @Test
    fun `renaming a tag to its own name is allowed`() =
        withTestApp {
            val tag = client.create("Rent").read<TagResponse>()
            val response = client.put("/api/tags/${tag.id}") { json(body("Rent", color = "Blue")) }
            assertEquals(HttpStatusCode.OK, response.status)
        }

    @Test
    fun `another user cannot see, change, or delete a tag`() =
        withTestApp {
            val tag = client.create("Rent").read<TagResponse>()
            val path = "/api/tags/${tag.id}"
            val other = "someone-else"

            assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
            assertEquals(HttpStatusCode.NotFound, client.put(path) { json(body("Mine")); asUser(other) }.status)
            assertEquals(HttpStatusCode.NotFound, client.delete(path) { asUser(other) }.status)
            assertEquals(emptyList(), client.get("/api/tags") { asUser(other) }.read<List<TagResponse>>())

            assertEquals("Rent", client.get(path).read<TagResponse>().name)
        }

    @Test
    fun `a deleted tag is gone`() =
        withTestApp {
            val tag = client.create("Rent").read<TagResponse>()

            assertEquals(HttpStatusCode.NoContent, client.delete("/api/tags/${tag.id}").status)
            assertEquals(HttpStatusCode.NotFound, client.get("/api/tags/${tag.id}").status)
            assertEquals(HttpStatusCode.NotFound, client.delete("/api/tags/${tag.id}").status)
        }

    @Test
    fun `unknown API paths and malformed ids get a JSON 404`() =
        withTestApp {
            val unknown = client.get("/api/nope")
            assertEquals(HttpStatusCode.NotFound, unknown.status)
            assertEquals("Not Found", unknown.read<ApiError>().error)

            assertEquals(HttpStatusCode.NotFound, client.get("/api/tags/not-a-guid").status)
        }
}
