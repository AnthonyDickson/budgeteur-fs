package budgeteur.shared

import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

/** The body of every error response. */
@Serializable
data class ApiError(
    val error: String,
    val details: String,
    val statusCode: Int?,
    val requestId: String,
)

/** UUIDs in their canonical lowercase form. */
object UuidSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("UUID", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString())

    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}

/**
 * Request and response bodies. Missing fields fail to decode, and nulls and
 * defaults are written rather than dropped, so every field is always present.
 */
val apiJson = Json {
    explicitNulls = true
    encodeDefaults = true
}
