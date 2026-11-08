package budgeteur

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import budgeteur.shared.ApiDocsSettings
import budgeteur.shared.AuthorizationStart
import budgeteur.shared.BEARER_AUTH
import budgeteur.shared.CookieSettings
import budgeteur.shared.Db
import budgeteur.shared.LoginConfig
import budgeteur.shared.OidcClient
import budgeteur.shared.PendingAuthorization
import budgeteur.shared.SessionKeys
import budgeteur.shared.UserPrincipal
import budgeteur.shared.apiJson
import io.ktor.client.HttpClient
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.URLBuilder
import io.ktor.http.contentType
import io.ktor.http.parseQueryString
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.net.URI
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.UUID

/** Acts as a different user against the same database, for the user scoping tests. */
const val TEST_USER_HEADER = "X-Test-User"
const val DEFAULT_TEST_USER = "test-user"

/**
 * Runs [block] against a migrated database in a temporary file, deleted afterwards. A file rather
 * than an in-memory database, so locking and WAL behave as in production.
 */
fun <T> withTempDb(block: (Db) -> T): T {
    val file = Files.createTempFile("budgeteur-test-", ".sqlite3")
    try {
        val db = Db("jdbc:sqlite:$file")
        db.migrate()
        return block(db)
    } finally {
        listOf("", "-wal", "-shm").forEach { Files.deleteIfExists(Path.of("$file$it")) }
    }
}

/** The client's origin in development, which the login returns to. */
const val TEST_RETURN_URL = "http://localhost:5173/"

const val FAKE_PROVIDER = "https://provider.test/authorize"

const val TEST_SCALAR_CLIENT = "scalar-docs"

/**
 * A provider that logs in whoever the authorization code names, so a test completes a login by
 * requesting the callback with `code=<user>` and the state from the redirect to [FAKE_PROVIDER].
 */
object FakeOidcClient : OidcClient {
    override fun startAuthorization(redirectUri: URI): AuthorizationStart {
        val state = UUID.randomUUID().toString()
        val uri =
            URLBuilder(FAKE_PROVIDER).apply {
                parameters.append("state", state)
                parameters.append("redirect_uri", redirectUri.toString())
            }
        return AuthorizationStart(
            URI(uri.buildString()),
            PendingAuthorization(state, "nonce", "verifier"),
        )
    }

    context(_: Raise<String>)
    override suspend fun completeAuthorization(
        callback: URI,
        redirectUri: URI,
        pending: PendingAuthorization,
    ): String {
        val query = parseQueryString(callback.rawQuery.orEmpty())
        query["error"]?.let { raise("the provider refused: $it") }
        ensure(query["state"] == pending.state) { "the response does not belong to this login" }
        return ensureNotNull(query["code"]) { "the response has no authorization code" }
    }
}

/**
 * Runs [block] against the app with a fresh database. Requests authenticate as [defaultUser], or
 * the user in the [TEST_USER_HEADER], as if with a bearer token. With no default, a request without
 * the header needs a session cookie.
 */
fun withTestApp(
    clock: () -> Instant = Instant::now,
    defaultUser: String? = DEFAULT_TEST_USER,
    block: suspend ApplicationTestBuilder.(db: Db) -> Unit,
) = withTempDb { db ->
    // Ktor builds the application lazily, on the first request, so read the start now.
    val startedAt = clock()
    testApplication {
        application {
            budgeteur(
                Dependencies(
                    db = db,
                    clock = clock,
                    environment = "Test",
                    startedAt = startedAt,
                    oidc = FakeOidcClient,
                    login = LoginConfig(TEST_RETURN_URL, logoutUrl = null),
                    callbackPath = "/signin-oidc",
                    cookies = CookieSettings(SessionKeys.random(), secure = false),
                    configureBearer = {
                        provider(BEARER_AUTH) {
                            authenticate { ctx ->
                                val user = ctx.call.request.headers[TEST_USER_HEADER] ?: defaultUser
                                if (user != null) ctx.principal(UserPrincipal(user))
                            }
                        }
                    },
                    apiDocs =
                        ApiDocsSettings(
                            TEST_SCALAR_CLIENT,
                            { URI("https://provider.test/authorize") },
                            { URI("https://provider.test/token") },
                        ),
                )
            )
        }
        block(db)
    }
}

/** A browser: keeps cookies and does not follow redirects, so a test can check each one. */
fun ApplicationTestBuilder.browser(): HttpClient = createClient {
    install(HttpCookies)
    followRedirects = false
}

fun HttpRequestBuilder.json(body: String) {
    contentType(ContentType.Application.Json)
    setBody(body)
}

fun HttpRequestBuilder.asUser(user: String) = header(TEST_USER_HEADER, user)

suspend inline fun <reified T> HttpResponse.read(): T = apiJson.decodeFromString(bodyAsText())
