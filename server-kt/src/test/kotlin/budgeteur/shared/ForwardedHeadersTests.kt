package budgeteur.shared

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.server.application.install
import io.ktor.server.plugins.origin
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import io.ktor.server.util.url
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ForwardedHeadersTests {
    @Test
    fun `loopback and private IPv4 peers are trusted proxies`() {
        listOf(
                "127.0.0.1",
                "127.1.2.3",
                "::1",
                "10.1.2.3",
                "172.16.0.1",
                "172.31.255.255",
                "192.168.1.10",
                "::ffff:172.17.0.1",
            )
            .forEach { assertTrue(isTrustedProxy(it), it) }
    }

    @Test
    fun `public addresses and host names are not`() {
        listOf("8.8.8.8", "172.32.0.1", "192.169.0.1", "2001:db8::1", "fd00::1", "localhost", "")
            .forEach { assertFalse(isTrustedProxy(it), it) }
    }

    /** Responds with the URL the app builds for the request and the client address it sees. */
    private fun withEcho(trusted: Boolean, block: suspend ApplicationTestBuilder.() -> Unit) =
        testApplication {
            application {
                install(TrustedForwardedHeaders) { isTrusted = { trusted } }
                routing {
                    get("/echo") {
                        call.respondText("${call.url()} ${call.request.origin.remoteAddress}")
                    }
                }
            }
            block()
        }

    private suspend fun ApplicationTestBuilder.echo(host: String): String =
        client
            .get("/echo") {
                header(HttpHeaders.Host, host)
                // The client's own values come first; the proxy appends the real ones.
                header(HttpHeaders.XForwardedProto, "http, https")
                header(HttpHeaders.XForwardedFor, "6.6.6.6, 203.0.113.7")
            }
            .bodyAsText()

    @Test
    fun `a trusted proxy's scheme and client address are used`() =
        withEcho(trusted = true) {
            assertEquals("https://budget.example.com/echo 203.0.113.7", echo("budget.example.com"))
            assertEquals(
                "https://budget.example.com:8443/echo 203.0.113.7",
                echo("budget.example.com:8443"),
            )
        }

    @Test
    fun `another peer's forwarded headers are ignored`() =
        withEcho(trusted = false) {
            assertEquals("http://budget.example.com/echo localhost", echo("budget.example.com"))
        }
}
