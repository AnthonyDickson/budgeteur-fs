package budgeteur.shared

import budgeteur.read
import budgeteur.withTestApp
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.server.request.receiveText
import io.ktor.server.response.respond
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals

/** A tag whose JSON body is about [bytes] long. */
private fun tagBody(bytes: Int) =
    """{"name":"${"a".repeat(bytes)}","color":"Red","kind":"Expense"}"""

class BodyLimitTests {
    @Test
    fun `a body whose length exceeds the default limit is a 413`() = withTestApp {
        val response =
            client.post("/api/tags") {
                contentType(ContentType.Application.Json)
                setBody(tagBody(DEFAULT_BODY_LIMIT.toInt()))
            }
        assertEquals(HttpStatusCode.PayloadTooLarge, response.status)
        assertEquals("Payload Too Large", response.read<ApiError>().error)
    }

    @Test
    fun `a body without a length is cut off at the limit`() = withTestApp {
        val response =
            client.post("/api/tags") {
                contentType(ContentType.Application.Json)
                // A channel has no length, so the client sends the body chunked.
                setBody(ByteReadChannel(tagBody(DEFAULT_BODY_LIMIT.toInt()).toByteArray()))
            }
        assertEquals(HttpStatusCode.PayloadTooLarge, response.status)
        assertEquals("Payload Too Large", response.read<ApiError>().error)
    }

    @Test
    fun `a route can raise its own limit`() = withTestApp {
        routing {
            route("/test/large") {
                bodyLimit(4 * DEFAULT_BODY_LIMIT)
                post { call.respond(call.receiveText().length) }
            }
        }

        val body = "a".repeat(2 * DEFAULT_BODY_LIMIT.toInt())
        val response = client.post("/test/large") { setBody(body) }
        assertEquals(HttpStatusCode.OK, response.status)
    }
}
