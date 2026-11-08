package budgeteur.shared

import io.ktor.http.HttpHeaders
import io.ktor.http.URLProtocol
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.application.hooks.CallSetup
import io.ktor.server.plugins.mutableOriginConnectionPoint
import java.net.Inet4Address
import java.net.InetAddress

private val IPV4_LITERAL = Regex("""\d{1,3}(\.\d{1,3}){3}""")

/**
 * Whether [address], the peer's IP address, is a proxy whose forwarded headers to trust: loopback
 * (`127.0.0.0/8`, `::1`), which covers a proxy on the same host, or the private IPv4 ranges
 * (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), which cover one reaching a container through a
 * published port. The same networks as the F# server. Only IP literals are parsed, so a host name
 * never triggers a DNS lookup.
 */
fun isTrustedProxy(address: String): Boolean {
    if (!IPV4_LITERAL.matches(address) && ':' !in address) return false
    // A literal never resolves through DNS. An IPv4-mapped IPv6 address parses as IPv4.
    val ip = runCatching { InetAddress.getByName(address) }.getOrNull() ?: return false
    return ip.isLoopbackAddress || (ip is Inet4Address && ip.isSiteLocalAddress)
}

class TrustedForwardedHeadersConfig {
    /** Decides from the peer's address whether to honour its forwarded headers. */
    var isTrusted: (String) -> Boolean = ::isTrustedProxy
}

/** A header's last value: the one the proxy nearest the server added. */
private fun ApplicationCall.lastForwarded(header: String): String? =
    request.headers
        .getAll(header)
        ?.flatMap { it.split(',') }
        ?.lastOrNull()
        ?.trim()
        ?.takeIf(String::isNotEmpty)

/**
 * Applies `X-Forwarded-Proto` and `X-Forwarded-For` from a trusted proxy, so the login builds
 * `https://` callback URLs behind a proxy that terminates TLS. Like ASP.NET Core's forwarded
 * headers middleware with its defaults, it takes the last value, since earlier ones come from the
 * client, and ignores the headers from any other peer. The proxy must pass the Host header through.
 *
 * Ktor's XForwardedHeaders plugin cannot check the peer, and keeps the port of the connection's
 * scheme when the scheme changes, which would put `:80` into an `https://` URL.
 */
val TrustedForwardedHeaders =
    createApplicationPlugin("TrustedForwardedHeaders", ::TrustedForwardedHeadersConfig) {
        val isTrusted = pluginConfig.isTrusted

        on(CallSetup) { call ->
            if (!isTrusted(call.request.local.remoteAddress)) return@on
            val origin = call.mutableOriginConnectionPoint

            call.lastForwarded(HttpHeaders.XForwardedProto)?.lowercase()?.let { scheme ->
                val protocol = URLProtocol.byName[scheme]
                if (protocol == URLProtocol.HTTP || protocol == URLProtocol.HTTPS) {
                    origin.scheme = scheme
                    // A Host header without a port means the scheme's default port.
                    val hostPort =
                        call.request.headers[HttpHeaders.Host]
                            ?.substringAfterLast(':', "")
                            ?.toIntOrNull()
                    origin.serverPort = hostPort ?: protocol.defaultPort
                }
            }

            call.lastForwarded(HttpHeaders.XForwardedFor)?.let { client ->
                origin.remoteHost = client
                origin.remoteAddress = client
            }
        }
    }
