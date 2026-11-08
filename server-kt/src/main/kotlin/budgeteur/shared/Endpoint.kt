package budgeteur.shared

import arrow.core.Either
import arrow.core.raise.Raise
import arrow.core.raise.either
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.util.AttributeKey
import java.sql.SQLException
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import org.sqlite.SQLiteErrorCode
import org.sqlite.SQLiteException

private val requestIdKey = AttributeKey<String>("RequestId")

/** Identifies the request in error bodies, so a user can quote it. */
val ApplicationCall.requestId: String
    get() = attributes.computeIfAbsent(requestIdKey) { UUID.randomUUID().toString() }

/**
 * Runs a handler written in Arrow's Raise DSL and turns its outcome into a
 * response. The handler writes its own success response; this writes every
 * failure, so no exception escapes a handler.
 */
object Endpoint {
    private fun fromException(log: RequestLog, e: Exception): DomainError =
        when {
            e is SQLiteException && e.resultCode.code and 0xff == SQLiteErrorCode.SQLITE_CONSTRAINT.code -> {
                log.warn("Unhandled constraint violation: ${e.message}", "exception" to e.toString())
                DomainError.Conflict(e)
            }
            e is SQLException -> DomainError.DatabaseError(e)
            else -> DomainError.UnhandledException(e)
        }

    private suspend fun run(call: ApplicationCall, handler: suspend Raise<DomainError>.() -> Unit): Either<DomainError, Unit> =
        try {
            either { handler() }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Either.Left(fromException(call.log, e))
        }

    private fun internalError(log: RequestLog, errorType: String, cause: Throwable): Triple<HttpStatusCode, String, String> {
        log.error(cause.stackTraceToString(), "errorType" to errorType)
        return Triple(HttpStatusCode.InternalServerError, "Internal Server Error", "An unexpected error occurred")
    }

    /**
     * A GUID path parameter. A malformed one gets the 404 an unmatched route
     * would, as Oxpecker's typed routes do.
     */
    fun Raise<DomainError>.uuidParam(call: ApplicationCall, name: String): UUID {
        val raw = call.parameters[name]
        return runCatching { UUID.fromString(raw) }.getOrNull()
            ?: raise(DomainError.NotFound("No API endpoint matches ${call.request.local.uri}"))
    }

    suspend fun handle(call: ApplicationCall, handler: suspend Raise<DomainError>.() -> Unit) {
        val error = run(call, handler).leftOrNull() ?: return
        val log = call.log
        val (status, title, details) =
            when (error) {
                is DomainError.ValidationFailed -> {
                    log.warn("Validation failed: ${error.message}", "errorType" to "ValidationFailed")
                    Triple(HttpStatusCode.BadRequest, "Validation Error", error.message)
                }
                is DomainError.NotFound -> {
                    log.warn("Not found: ${error.message}", "errorType" to "NotFound")
                    Triple(HttpStatusCode.NotFound, "Not Found", error.message)
                }
                DomainError.Unauthorised -> {
                    log.error("Got a request where the user claims were not defined")
                    Triple(HttpStatusCode.Unauthorized, "Unauthorized", "Did not find claims in the request data")
                }
                is DomainError.Conflict -> {
                    log.warn("Conflict: ${error.cause}", "errorType" to "Conflict")
                    Triple(
                        HttpStatusCode.Conflict,
                        "Conflict",
                        "The request could not be completed due to unhandled database constraint violations.",
                    )
                }
                is DomainError.DatabaseError -> internalError(log, "DatabaseError", error.cause)
                is DomainError.UnhandledException -> internalError(log, "UnhandledException", error.cause)
            }
        Json.write(call, ApiError(title, details, status.value, call.requestId), status)
    }
}
