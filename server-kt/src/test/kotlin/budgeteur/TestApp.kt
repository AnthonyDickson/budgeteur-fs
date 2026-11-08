package budgeteur

import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.apiJson
import budgeteur.shared.UserPrincipal
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.time.Instant
import java.util.UUID

/** Acts as a different user against the same database, for the user scoping tests. */
const val TEST_USER_HEADER = "X-Test-User"
const val DEFAULT_TEST_USER = "test-user"

/**
 * Runs [block] against the app with a fresh in-memory database. SQLite drops a
 * shared-cache in-memory database when its last connection closes, and each
 * query opens its own, so a keeper connection stays open for the test.
 */
fun withTestApp(
    clock: () -> Instant = Instant::now,
    block: suspend ApplicationTestBuilder.(db: Db) -> Unit,
) {
    val db = Db("jdbc:sqlite:file:test-${UUID.randomUUID()}?mode=memory&cache=shared")
    // Ktor builds the application lazily, on the first request, so read the start now.
    val startedAt = clock()
    db.open().use {
        db.migrate()
        testApplication {
            application {
                budgeteur(
                    Dependencies(
                        db = db,
                        clock = clock,
                        environment = "Test",
                        startedAt = startedAt,
                        configureAuth = {
                            provider(Auth.PROVIDER) {
                                authenticate { ctx ->
                                    val user = ctx.call.request.headers[TEST_USER_HEADER] ?: DEFAULT_TEST_USER
                                    ctx.principal(UserPrincipal(user))
                                }
                            }
                        },
                    ),
                )
            }
            block(db)
        }
    }
}

fun HttpRequestBuilder.json(body: String) {
    contentType(ContentType.Application.Json)
    setBody(body)
}

fun HttpRequestBuilder.asUser(user: String) = header(TEST_USER_HEADER, user)

suspend inline fun <reified T> HttpResponse.read(): T = apiJson.decodeFromString(bodyAsText())
