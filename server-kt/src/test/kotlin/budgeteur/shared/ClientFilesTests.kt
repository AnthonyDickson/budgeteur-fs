package budgeteur.shared

import budgeteur.read
import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.deleteRecursively
import kotlin.io.path.writeText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private const val INDEX = "<!doctype html><title>Budgeteur</title>"
private const val BUNDLE = "console.log('app')"

/** Runs [block] against a client build with an index page and one hashed bundle. */
@OptIn(kotlin.io.path.ExperimentalPathApi::class)
private fun withClientBuild(block: (Path) -> Unit) {
    val root = Files.createTempDirectory("budgeteur-client-")
    try {
        root.resolve(CLIENT_INDEX).writeText(INDEX)
        root.resolve("assets").createDirectories().resolve("app-3f2a.js").writeText(BUNDLE)
        block(root)
    } finally {
        root.deleteRecursively()
    }
}

private fun HttpResponse.cacheControl() = headers[HttpHeaders.CacheControl]

class ClientFilesTests {
    @Test
    fun `the root serves the index page, revalidated on each use`() = withClientBuild { root ->
        withTestApp(webRoot = root) {
            val response = client.get("/")
            assertEquals(HttpStatusCode.OK, response.status)
            assertEquals(INDEX, response.bodyAsText())
            assertEquals("no-cache", response.cacheControl())
        }
    }

    @Test
    fun `a client route serves the index page`() = withClientBuild { root ->
        withTestApp(webRoot = root) {
            val response = client.get("/transactions/search")
            assertEquals(HttpStatusCode.OK, response.status)
            assertEquals(INDEX, response.bodyAsText())
            assertEquals("no-cache", response.cacheControl())
        }
    }

    @Test
    fun `a hashed bundle is cached for good`() = withClientBuild { root ->
        withTestApp(webRoot = root) {
            val response = client.get("/assets/app-3f2a.js")
            assertEquals(HttpStatusCode.OK, response.status)
            assertEquals(BUNDLE, response.bodyAsText())
            assertTrue(response.cacheControl().orEmpty().contains("max-age=31536000"))
        }
    }

    @Test
    fun `a missing file is a 404, not the index page`() = withClientBuild { root ->
        withTestApp(webRoot = root) {
            assertEquals(HttpStatusCode.NotFound, client.get("/assets/gone-1234.js").status)
        }
    }

    @Test
    fun `an unknown API path stays a JSON 404`() = withClientBuild { root ->
        withTestApp(webRoot = root) {
            val response = client.get("/api/nope")
            assertEquals(HttpStatusCode.NotFound, response.status)
            assertEquals("Not Found", response.read<ApiError>().error)
        }
    }

    @Test
    fun `a web root without an index page is a config error`() {
        val empty = Files.createTempDirectory("budgeteur-empty-")
        try {
            val failures =
                loadConfig(mapOf("BUDGETEUR_WEB_ROOT" to empty.toString())).leftOrNull().orEmpty()
            assertTrue(failures.any { it.startsWith("BUDGETEUR_WEB_ROOT") }, failures.toString())
        } finally {
            Files.delete(empty)
        }
    }
}
