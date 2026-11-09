package budgeteur.feature.quicktag

import budgeteur.domain.Categorisation
import budgeteur.shared.Db
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
import kotlinx.serialization.Serializable

@Serializable
@JsonSchema.Description("Payload for marking a transaction as a transfer.")
data class MarkTransferRequest(
    @JsonSchema.Description(QuickTagDocs.SUGGESTED) val suggested: Boolean
)

fun Route.markTransfer(db: Db) =
    put("/api/quick-tag/{id}/transfer") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val request = call.receiveOrRaise<MarkTransferRequest>()

                db.transaction {
                    saveChoice(userId, id, Categorisation.onTransfer(request.suggested))
                }

                call.log.info("Marked transaction $id as a transfer", "transactionId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Mark a transaction as a transfer"
            description =
                "Records that the transaction moves money between the user's own accounts, " +
                    "replacing any categorisation. The source is Accepted when a transfer was " +
                    "the row's suggestion, otherwise Manual. A transfer is neither income nor " +
                    "expense and is not in the quick tagging queue. Returns 204 on success."
            tag("Quick tagging")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<MarkTransferRequest>()
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
