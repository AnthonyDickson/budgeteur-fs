@file:UseSerializers(UuidSerializer::class)

package budgeteur.feature.quicktag

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.withError
import budgeteur.data.readRules
import budgeteur.domain.RuleTarget
import budgeteur.domain.formatCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.EnumOf
import budgeteur.shared.MONEY_PATTERN
import budgeteur.shared.UuidSerializer
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.JsonType
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import java.util.UUID
import kotlin.uuid.Uuid
import kotlin.uuid.toJavaUuid
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers

@Serializable
@JsonSchema.Description("What a rule suggests for a queued transaction.")
data class SuggestionResponse(
    @JsonSchema.Description(QuickTagDocs.TARGET) @EnumOf(RuleTarget.Kind::class) val target: String,
    @JsonSchema.Description(QuickTagDocs.TAG_ID) @JsonSchema.Format("uuid") val tagId: UUID?,
    @JsonSchema.Description("The pattern of the rule that suggests it.") val pattern: String,
)

@Serializable
@JsonSchema.Description("A transaction waiting for a tag.")
data class QueuedTransactionResponse(
    @JsonSchema.Format("uuid") val id: UUID,
    @JsonSchema.Description("A debit (negative) or credit (positive), as a decimal string.")
    @JsonSchema.Pattern(MONEY_PATTERN)
    val amount: String,
    val description: String,
    @JsonSchema.Description("The calendar day the transaction occurred.")
    @JsonSchema.Format(DATE_FORMAT)
    val date: String,
    @JsonSchema.Description("The name of the transaction's account, if it has one.")
    val accountName: String?,
    // Described on the type, so Ktor documents it once.
    val suggestion: SuggestionResponse?,
)

@Serializable
@JsonSchema.Description("How many queued transactions are suggested a categorisation.")
data class SuggestionCountResponse(
    @JsonSchema.Description(QuickTagDocs.TARGET) @EnumOf(RuleTarget.Kind::class) val target: String,
    @JsonSchema.Description(QuickTagDocs.TAG_ID) @JsonSchema.Format("uuid") val tagId: UUID?,
    val count: Int,
)

@Serializable
@JsonSchema.Description("A batch of the quick tagging queue.")
data class QueueResponse(
    @JsonSchema.Description(
        "Up to 50 of the user's untagged transactions, newest first, only those suggested the " +
            "filter's categorisation when one is given. Tagging, dismissing, or marking them as " +
            "transfers removes them from the queue, so fetching again returns the next batch."
    )
    val transactions: List<QueuedTransactionResponse>,
    @JsonSchema.Description(
        "How many transactions the whole queue holds, or how many are suggested the filter's " +
            "categorisation."
    )
    val total: Int,
    @JsonSchema.Description(
        "How many queued transactions are suggested each categorisation, over the whole queue " +
            "whatever the filter: expense tags, then income tags, each by name, then transfer."
    )
    val suggestions: List<SuggestionCountResponse>,
)

private fun Parameters.nonBlank(name: String): String? = get(name)?.takeIf { it.isNotBlank() }

/** The optional filter: a target and, for a tag, its id, validated as for rules. */
context(_: Raise<DomainError>)
private fun parseFilter(query: Parameters): RuleTarget? {
    val target = query.nonBlank("target")
    val rawTagId = query.nonBlank("tagId")
    if (target == null) {
        ensure(rawTagId == null) {
            DomainError.ValidationFailed("The query parameter 'tagId' needs a 'target'")
        }
        return null
    }
    val tagId = rawTagId?.let {
        ensureNotNull(Uuid.parseHexDashOrNull(it)?.toJavaUuid()) {
            DomainError.ValidationFailed("The query parameter 'tagId' must be a GUID, got '$it'")
        }
    }
    return withError(DomainError::ValidationFailed) { RuleTarget.create(target, tagId) }
}

private fun Suggestion.toResponse() =
    SuggestionResponse(target.kind.name, target.tagId, pattern.value)

private fun Suggested<Queued>.toResponse(): QueuedTransactionResponse {
    val (transaction, accountName) = this.transaction
    return QueuedTransactionResponse(
        id = transaction.id,
        amount = transaction.amount.toString(),
        description = transaction.description.value,
        date = transaction.date.formatCalendarDate(),
        accountName = accountName,
        suggestion = suggestion?.toResponse(),
    )
}

fun Route.readQueue(db: Db) =
    get("/api/quick-tag") {
            call.handle {
                val userId = call.userId
                val filter = parseFilter(call.request.queryParameters)

                val read = db.sql {
                    readQueue(
                        BATCH_SIZE,
                        readRules(userId),
                        readTags(userId),
                        { it.transaction.description },
                        filter,
                        readQueued(userId),
                    )
                }

                call.log.info(
                    "Returned ${read.batch.size} of ${read.total} queued transactions",
                    "total" to read.total,
                )
                call.respond(
                    QueueResponse(
                        transactions = read.batch.map { it.toResponse() },
                        total = read.total,
                        suggestions =
                            read.counts.map { (target, count) ->
                                SuggestionCountResponse(target.kind.name, target.tagId, count)
                            },
                    )
                )
            }
        }
        .describe {
            summary = "Read the quick tagging queue"
            description =
                "Returns the first batch of the user's untagged transactions, newest first, each " +
                    "with the suggestion of the winning rule, and how many the queue holds. Also " +
                    "returns how many queued transactions are suggested each categorisation, " +
                    "over the whole queue. With a target, returns only the transactions " +
                    "suggested it, and their total. Transfers have a categorisation, so they are " +
                    "not in the queue."
            tag("Quick tagging")
            parameters {
                query("target") {
                    description =
                        "Only transactions suggested this categorisation: Tag or Transfer."
                    schema = JsonSchema(type = JsonType.STRING)
                }
                query("tagId") {
                    description =
                        "The suggested tag, required with the Tag target and rejected with " +
                            "Transfer."
                    schema = JsonSchema(type = JsonType.STRING, format = "uuid")
                }
            }
            responses {
                json<QueueResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
