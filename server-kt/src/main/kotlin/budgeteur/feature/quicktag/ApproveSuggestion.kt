@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.quicktag

import arrow.core.raise.context.ensure
import arrow.core.raise.context.raise
import arrow.core.raise.context.withError
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.data.saveCategorisation
import budgeteur.domain.Categorisation
import budgeteur.domain.RuleTarget
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.UuidSerializer
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
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description("Payload for approving a suggestion for the queued transactions shown.")
data class ApprovalRequest(
    @JsonSchema.Description(QuickTagDocs.TARGET) @EnumOf(RuleTarget.Kind::class) val target: String,
    @JsonSchema.Description(QuickTagDocs.TAG_ID) @JsonSchema.Format("uuid") val tagId: UUID? = null,
    @JsonSchema.Description("The transactions to approve it for: at most a batch of the queue.")
    @JsonSchema.MaxItems(BATCH_SIZE)
    val transactionIds: List<UUID>,
)

@Serializable
@JsonSchema.Description("What an approval changed.")
data class ApprovalResponse(
    @JsonSchema.Description(
        "How many of the transactions were still in the queue and got the categorisation."
    )
    val changed: Int
)

fun Route.approveSuggestion(db: Db) =
    post("/api/quick-tag/approvals") {
            call.handle {
                val userId = call.userId
                val request = call.receiveOrRaise<ApprovalRequest>()
                val target =
                    withError(DomainError::ValidationFailed) {
                        RuleTarget.create(request.target, request.tagId)
                    }
                ensure(request.transactionIds.size <= BATCH_SIZE) {
                    DomainError.ValidationFailed(
                        "An approval can list at most $BATCH_SIZE transactions"
                    )
                }
                val ids = request.transactionIds.distinct()

                // Every id must be the user's, checked before the write, so one deleted since the
                // page was read fails the whole request. One categorised meanwhile, in another
                // tab, is not in the queue, so it is skipped rather than overwritten.
                val changed = db.transaction {
                    requireAll({ requireTagIfReferenced(userId, target.tagId) })
                    val found =
                        select(TRANSACTIONS.ID, CATEGORISATIONS.TRANSACTION_ID)
                            .from(TRANSACTIONS)
                            .leftJoin(CATEGORISATIONS)
                            .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
                            .where(TRANSACTIONS.USER_ID.eq(userId), TRANSACTIONS.ID.`in`(ids))
                            .fetch { checkNotNull(it.value1()) to (it.value2() == null) }
                            .toMap()
                    ids.firstOrNull { it !in found }
                        ?.let { raise(DomainError.NotFound("Transaction $it not found")) }
                    val queued = ids.filter { found.getValue(it) }
                    queued.forEach {
                        saveCategorisation(userId, it, Categorisation.onApprove(target))
                    }
                    queued.size
                }

                call.log.info(
                    "Approved ${request.target} for $changed transactions",
                    "changed" to changed,
                )
                call.respond(ApprovalResponse(changed))
            }
        }
        .describe {
            summary = "Approve a suggestion"
            description =
                "Gives the listed transactions that are still in the quick tagging queue the tag " +
                    "or transfer, with the Accepted source, in one database transaction, and " +
                    "returns how many changed. Transactions categorised since the queue was read " +
                    "are skipped. Lists more than a batch of 50, or a tag the user does not have, " +
                    "are 400; any transaction the user does not have is 404, and nothing is " +
                    "written."
            tag("Quick tagging")
            requestBody {
                required = true
                schema = jsonSchema<ApprovalRequest>()
            }
            responses {
                json<ApprovalResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
