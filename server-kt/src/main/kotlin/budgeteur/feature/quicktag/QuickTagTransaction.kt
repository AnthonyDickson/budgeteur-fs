@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.quicktag

import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.domain.Categorisation
import budgeteur.shared.Db
import budgeteur.shared.UuidSerializer
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.noContent
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.put
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description("Payload for quick tagging a transaction.")
data class QuickTagRequest(
    @JsonSchema.Description("The tag to give the transaction.")
    @JsonSchema.Format("uuid")
    val tagId: UUID,
    @JsonSchema.Description(QuickTagDocs.SUGGESTED) val suggested: Boolean,
)

/** Field descriptions the requests share. */
internal object QuickTagDocs {
    const val SUGGESTED =
        "Whether the choice was the row's suggestion, so it records that the user accepted it."
    const val TARGET = "The categorisation: a tag, or a transfer."
    const val TAG_ID = "The tag. Required for the Tag target, and absent for Transfer."
}

fun Route.quickTagTransaction(db: Db) =
    put("/api/quick-tag/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val request = call.receiveOrRaise<QuickTagRequest>()

                db.transaction {
                    requireAll({ requireTagIfReferenced(userId, request.tagId) })
                    saveChoice(
                        userId,
                        id,
                        Categorisation.onQuickTag(request.tagId, request.suggested),
                    )
                }

                call.log.info("Quick tagged transaction $id", "transactionId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Quick tag a transaction"
            description =
                "Gives the transaction the tag as the user's decision, replacing any " +
                    "categorisation it had. The source is Accepted when the tag was the row's " +
                    "suggestion, otherwise Manual. Returns 204 on success."
            tag("Quick tagging")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<QuickTagRequest>()
            }
            responses {
                noContent()
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
