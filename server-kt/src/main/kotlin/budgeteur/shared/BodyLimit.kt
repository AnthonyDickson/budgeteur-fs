package budgeteur.shared

import io.ktor.server.application.install
import io.ktor.server.plugins.bodylimit.RequestBodyLimit
import io.ktor.server.routing.Route

/** The cap on request bodies, unless a route sets its own with [bodyLimit]. */
const val DEFAULT_BODY_LIMIT: Long = 64 * 1024

/**
 * Caps the bodies of requests to this route and its children. The routing root sets
 * [DEFAULT_BODY_LIMIT]; an endpoint that needs more sets its own limit, which overrides the
 * enclosing one for that endpoint, rather than raising the default.
 *
 * A request whose `Content-Length` exceeds the limit is refused before the handler runs; a body
 * without one is cut off once it passes the limit. Both are a 413 from [apiErrors].
 */
fun Route.bodyLimit(bytes: Long) {
    install(RequestBodyLimit) { bodyLimit { bytes } }
}
