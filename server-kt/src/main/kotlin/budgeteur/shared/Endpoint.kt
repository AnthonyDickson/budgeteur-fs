package budgeteur.shared

import arrow.core.raise.Raise
import arrow.core.raise.either
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.statuspages.StatusPagesConfig
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.util.AttributeKey
import java.sql.SQLException
import java.util.UUID
import org.sqlite.SQLiteErrorCode
import org.sqlite.SQLiteException

private val requestIdKey = AttributeKey<String>("RequestId")

/** Identifies the request in error bodies, so a user can quote it. */
val ApplicationCall.requestId: String
    get() = attributes.computeIfAbsent(requestIdKey) { UUID.randomUUID().toString() }

suspend fun ApplicationCall.respondError(status: HttpStatusCode, title: String, details: String) =
    respond(status, ApiError(title, details, status.value, requestId))

/**
 * Runs a handler written in Arrow's Raise DSL. The handler writes its own
 * success response; this writes the error a handler raises. Exceptions are
 * left to [apiErrors].
 */
object Endpoint {
    /**
     * A UUID path parameter. A malformed one gets a 404, as for a path that
     * matches no route.
     */
    fun Raise<DomainError>.uuidParam(call: ApplicationCall, name: String): UUID {
        val raw = call.parameters[name]
        return runCatching { UUID.fromString(raw) }.getOrNull()
            ?: raise(DomainError.NotFound("No API endpoint matches ${call.request.local.uri}"))
    }

    /** The request body. One that does not decode to [T] is a validation failure. */
    suspend inline fun <reified T : Any> Raise<DomainError>.body(call: ApplicationCall): T =
        try {
            call.receive<T>()
        } catch (e: BadRequestException) {
            raise(DomainError.ValidationFailed(e.cause?.message ?: e.message ?: "Invalid request body"))
        }

    suspend fun handle(call: ApplicationCall, handler: suspend Raise<DomainError>.() -> Unit) {
        val error = either { handler() }.leftOrNull() ?: return
        val log = call.log
        when (error) {
            is DomainError.ValidationFailed -> {
                log.warn("Validation failed: ${error.message}", "errorType" to "ValidationFailed")
                call.respondError(HttpStatusCode.BadRequest, "Validation Error", error.message)
            }
            is DomainError.NotFound -> {
                log.warn("Not found: ${error.message}", "errorType" to "NotFound")
                call.respondError(HttpStatusCode.NotFound, "Not Found", error.message)
            }
            DomainError.Unauthorised -> {
                log.error("Got a request where the user claims were not defined")
                call.respondError(HttpStatusCode.Unauthorized, "Unauthorized", "Did not find claims in the request data")
            }
        }
    }
}

/**
 * Turns an exception that escapes a handler into a JSON error. A constraint
 * violation is a 409: handlers check constraints first, so one that reaches
 * here marks a missed check rather than a broken server.
 */
fun StatusPagesConfig.apiErrors() {
    exception<Throwable> { call, cause ->
        // jOOQ wraps the driver's exceptions in its own, so look through the causes.
        val sqlError = generateSequence(cause) { it.cause }.filterIsInstance<SQLException>().firstOrNull()
        if (sqlError is SQLiteException && sqlError.resultCode.code and 0xff == SQLiteErrorCode.SQLITE_CONSTRAINT.code) {
            call.log.warn("Unhandled constraint violation: ${sqlError.message}", "errorType" to "Conflict")
            call.respondError(
                HttpStatusCode.Conflict,
                "Conflict",
                "The request could not be completed due to unhandled database constraint violations.",
            )
        } else {
            val errorType = if (sqlError != null) "DatabaseError" else "UnhandledException"
            call.log.error(cause.stackTraceToString(), "errorType" to errorType)
            call.respondError(HttpStatusCode.InternalServerError, "Internal Server Error", "An unexpected error occurred")
        }
    }
}
