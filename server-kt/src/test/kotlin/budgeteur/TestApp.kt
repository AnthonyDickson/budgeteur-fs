package budgeteur

import budgeteur.shared.Db
import budgeteur.shared.USER_AUTH
import budgeteur.shared.UserPrincipal
import budgeteur.shared.apiJson
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

/** Acts as a different user against the same database, for the user scoping tests. */
const val TEST_USER_HEADER = "X-Test-User"
const val DEFAULT_TEST_USER = "test-user"

/**
 * Runs [block] against a migrated database in a temporary file, deleted
 * afterwards. A file rather than an in-memory database, so locking and WAL
 * behave as in production.
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

/** Runs [block] against the app with a fresh database. */
fun withTestApp(
    clock: () -> Instant = Instant::now,
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
                    configureAuth = {
                        provider(USER_AUTH) {
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

fun HttpRequestBuilder.json(body: String) {
    contentType(ContentType.Application.Json)
    setBody(body)
}

fun HttpRequestBuilder.asUser(user: String) = header(TEST_USER_HEADER, user)

suspend inline fun <reified T> HttpResponse.read(): T = apiJson.decodeFromString(bodyAsText())
