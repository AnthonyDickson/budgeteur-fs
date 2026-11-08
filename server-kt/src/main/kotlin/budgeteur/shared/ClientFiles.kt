package budgeteur.shared

import io.ktor.http.CacheControl
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.http.content.staticFiles
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.response.respondFile
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.hide
import java.io.File
import java.nio.file.Path

const val CLIENT_INDEX = "index.html"

/** Vite puts the bundles here, with a content hash in each name, so they never change. */
private const val HASHED_ASSETS_DIR = "assets"

private val immutable =
    CacheControl.MaxAge(
        maxAgeSeconds = 365 * 24 * 60 * 60,
        visibility = CacheControl.Visibility.Public,
    )

/**
 * Everything else, `index.html` above all, is revalidated on each use, so a deploy shows at once.
 */
private val revalidate = CacheControl.NoCache(null)

/**
 * Serves the client's build from [root], and `index.html` for any other path without a file
 * extension, so the SPA's own routes load on a refresh. A missing file (a path with an extension)
 * is a 404. Literal routes, `/api/...` among them, outrank this catch-all.
 */
fun Route.clientFiles(root: Path) {
    val dir = root.toFile()
    staticFiles("/", dir, index = CLIENT_INDEX) {
            cacheControl { file ->
                listOf(if (file.parentFile.name == HASHED_ASSETS_DIR) immutable else revalidate)
            }
            fallback { requestedPath, call ->
                if ('.' in requestedPath.substringAfterLast('/')) {
                    call.respond(HttpStatusCode.NotFound)
                } else {
                    call.response.header(HttpHeaders.CacheControl, revalidate.toString())
                    call.respondFile(File(dir, CLIENT_INDEX))
                }
            }
        }
        .hide()
}
