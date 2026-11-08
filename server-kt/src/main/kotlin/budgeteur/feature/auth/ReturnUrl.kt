package budgeteur.feature.auth

import java.net.URI

/*
 * Where a login returns to: the page the user was on, so an expired session does not drop them on
 * the dashboard.
 */

/**
 * Whether [url] is a path on this site, as ASP.NET Core's `IsLocalUrl` decides: it starts with a
 * single `/`, since `//host` and `/\host` name another host, and holds no control characters.
 */
fun isLocalPath(url: String): Boolean =
    url.startsWith("/") &&
        (url.length == 1 || (url[1] != '/' && url[1] != '\\')) &&
        url.none(Char::isISOControl)

/**
 * The URL to return to after logging in: [requested], a path from the client, resolved against
 * [baseUrl], the configured return URL. Anything other than a local path falls back to [baseUrl],
 * so the login cannot be used to redirect to another site.
 */
fun resolveReturnUrl(baseUrl: String, requested: String?): String =
    requested
        ?.takeIf(::isLocalPath)
        // A path that is not a valid URI reference, such as one with a space, falls back too.
        ?.let { path -> runCatching { URI(baseUrl).resolve(path).toString() }.getOrNull() }
        ?: baseUrl
