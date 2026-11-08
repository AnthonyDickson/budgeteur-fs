package budgeteur.shared

import arrow.core.Either
import arrow.core.left
import arrow.core.right
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.receiveText
import io.ktor.server.response.respondText
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json as KJson

@Serializable
data class ApiError(
    val error: String,
    val details: String,
    val statusCode: Int?,
    val requestId: String,
)

/** UUIDs on the wire are lowercase, as .NET writes them. */
object UuidSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("UUID", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString())

    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}

object Json {
    val format = KJson {
        // Mirror Thoth's auto coders: missing fields fail, nulls are written.
        explicitNulls = true
        encodeDefaults = true
    }

    suspend inline fun <reified T> write(
        call: ApplicationCall,
        value: T,
        status: HttpStatusCode = HttpStatusCode.OK,
    ) = call.respondText(format.encodeToString(value), ContentType.Application.Json, status)

    suspend inline fun <reified T> read(call: ApplicationCall): Either<DomainError, T> {
        val body = call.receiveText()
        return try {
            format.decodeFromString<T>(body).right()
        } catch (e: SerializationException) {
            DomainError.ValidationFailed(e.message ?: "Invalid JSON").left()
        } catch (e: IllegalArgumentException) {
            DomainError.ValidationFailed(e.message ?: "Invalid JSON").left()
        }
    }
}
