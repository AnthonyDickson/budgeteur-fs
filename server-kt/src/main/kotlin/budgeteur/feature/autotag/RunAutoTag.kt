package budgeteur.feature.autotag

import arrow.core.raise.context.withError
import budgeteur.data.readRules
import budgeteur.data.saveCategorisation
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.post
import kotlinx.serialization.Serializable

@Serializable
@JsonSchema.Description("Payload for an auto-tagging run.")
data class RunAutoTagRequest(
    @JsonSchema.Description(
        "TagUntagged applies rules to untagged transactions only. Retag recomputes every " +
            "transaction without a manual tag, so rule tags may change or be cleared."
    )
    @EnumOf(AutoTagAction::class)
    val action: String
)

@Serializable
@JsonSchema.Description("How many transactions a run changed.")
data class RunAutoTagResponse(
    @JsonSchema.Description("Untagged transactions that got a rule tag.") val tagged: Int,
    @JsonSchema.Description("Rule tags changed to another rule's tag.") val changed: Int,
    @JsonSchema.Description("Rule tags removed because no rule matches any more.") val cleared: Int,
)

fun Route.runAutoTag(db: Db) =
    post("/api/auto-tag") {
            call.handle {
                val userId = call.userId
                val request = call.receiveOrRaise<RunAutoTagRequest>()
                val action =
                    withError(DomainError::ValidationFailed) { AutoTagAction.parse(request.action) }

                // One IMMEDIATE transaction, so no other write lands between the read and the
                // write, and a manual tag set meanwhile cannot be overwritten.
                val counts = db.transaction {
                    val changes = changes(action, readRules(userId), readCandidates(userId))
                    changes.forEach { change ->
                        val after =
                            when (change) {
                                is Change.Tagged -> change.categorisation
                                is Change.Changed -> change.categorisation
                                is Change.Cleared -> null
                            }
                        saveCategorisation(userId, change.transactionId, after)
                    }
                    changes.counts()
                }

                call.log.info(
                    "Auto-tagged with $action: ${counts.tagged} tagged, ${counts.changed} " +
                        "changed, ${counts.cleared} cleared",
                    "tagged" to counts.tagged,
                    "changed" to counts.changed,
                    "cleared" to counts.cleared,
                )
                call.respond(RunAutoTagResponse(counts.tagged, counts.changed, counts.cleared))
            }
        }
        .describe {
            summary = "Run auto-tagging"
            description =
                "Applies the user's rules to their transactions and returns how many were " +
                    "tagged, changed, and cleared. Manual tags never change."
            tag("Auto-tagging")
            requestBody {
                required = true
                schema = jsonSchema<RunAutoTagRequest>()
            }
            responses {
                json<RunAutoTagResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
