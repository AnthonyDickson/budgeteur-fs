package budgeteur.auth

import budgeteur.TEST_RETURN_URL
import budgeteur.asUser
import budgeteur.browser
import budgeteur.feature.auth.LOGIN_PATH
import budgeteur.feature.auth.LOGOUT_PATH
import budgeteur.feature.auth.RETURN_URL_PARAMETER
import budgeteur.feature.auth.SIGNED_OUT_PATH
import budgeteur.feature.tag.TagResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

class LoginTests {
    private val HttpResponse.location: String?
        get() = headers[HttpHeaders.Location]

    /** Starts a login, returning the state the provider would send back. */
    private suspend fun HttpClient.startLogin(page: String? = null): String {
        val response = get(LOGIN_PATH) { page?.let { parameter(RETURN_URL_PARAMETER, it) } }
        assertEquals(HttpStatusCode.Found, response.status)
        return checkNotNull(Url(checkNotNull(response.location)).parameters["state"])
    }

    /** The provider's redirect back to the app after [user] logs in. */
    private suspend fun HttpClient.callback(user: String, state: String): HttpResponse =
        get("/signin-oidc") {
            parameter("code", user)
            parameter("state", state)
        }

    private suspend fun HttpClient.logIn(user: String, page: String? = null): HttpResponse =
        callback(user, startLogin(page))

    @Test
    fun `a user logs in through the provider, uses the API, and logs out`() =
        withTestApp(defaultUser = null) {
            val browser = browser()
            val signedOut = browser.get("/api/tags")
            assertEquals(HttpStatusCode.Unauthorized, signedOut.status)
            assertEquals("Unauthorized", signedOut.read<ApiError>().error)

            val callback = browser.logIn("alice", page = "/tags?sort=name#top")
            assertEquals(HttpStatusCode.Found, callback.status)
            assertEquals("${TEST_RETURN_URL}tags?sort=name#top", callback.location)

            // The session belongs to the user the provider named.
            browser.post("/api/tags") {
                json("""{"name": "Rent", "color": "Red", "kind": "Expense"}""")
            }
            val tags = client.get("/api/tags") { asUser("alice") }.read<List<TagResponse>>()
            assertEquals(listOf("Rent"), tags.map { it.name })

            // Logged in already, a login returns straight to the page.
            val again = browser.get(LOGIN_PATH) { parameter(RETURN_URL_PARAMETER, "/tags") }
            assertEquals("${TEST_RETURN_URL}tags", again.location)

            val logout = browser.post(LOGOUT_PATH)
            assertEquals(SIGNED_OUT_PATH, logout.location)
            assertEquals(HttpStatusCode.Unauthorized, browser.get("/api/tags").status)
        }

    @Test
    fun `a callback must match the login it completes, and completes it once`() =
        withTestApp(defaultUser = null) {
            val browser = browser()
            val state = browser.startLogin()

            val forged = browser.callback("mallory", "forged-state")
            assertEquals(HttpStatusCode.BadRequest, forged.status)
            assertContains(forged.read<ApiError>().details, "does not belong to this login")

            // The failed callback used up the attempt.
            val retried = browser.callback("alice", state)
            assertEquals(HttpStatusCode.BadRequest, retried.status)
            assertContains(retried.read<ApiError>().details, "no login is in progress")
            assertEquals(HttpStatusCode.Unauthorized, browser.get("/api/tags").status)
        }

    @Test
    fun `a session ends after an hour without requests, and each request extends it`() {
        val start = Instant.parse("2026-01-01T00:00:00Z")
        var now = start
        withTestApp(clock = { now }, defaultUser = null) {
            val browser = browser()
            browser.logIn("alice")

            now = start + Duration.ofMinutes(40)
            assertEquals(HttpStatusCode.OK, browser.get("/api/tags").status)

            // Past the first hour, but within an hour of the last request.
            now = start + Duration.ofMinutes(99)
            assertEquals(HttpStatusCode.OK, browser.get("/api/tags").status)

            now = start + Duration.ofMinutes(99 + 61)
            assertEquals(HttpStatusCode.Unauthorized, browser.get("/api/tags").status)
        }
    }
}
