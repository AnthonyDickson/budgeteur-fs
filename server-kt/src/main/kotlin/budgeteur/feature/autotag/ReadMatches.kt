package budgeteur.feature.autotag

import arrow.core.raise.context.withError
import budgeteur.domain.RulePattern
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.JsonSchema
import io.ktor.openapi.JsonType
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe
import kotlinx.serialization.Serializable

@Serializable
@JsonSchema.Description("What a rule pattern matches among the user's transactions.")
data class MatchesResponse(
    @JsonSchema.Description("How many of the user's non-transfer transactions the pattern matches.")
    val count: Int,
    @JsonSchema.Description(
        "How many non-transfer transactions the user has, so the count can be read as a share."
    )
    val total: Int,
    @JsonSchema.Description(
        "Up to five distinct descriptions from the most recent matches, most recent first."
    )
    val samples: List<String>,
)

fun Route.readMatches(db: Db) =
    get("/api/auto-tag/matches") {
            call.handle {
                val userId = call.userId
                val pattern =
                    withError(DomainError::ValidationFailed) {
                        RulePattern.create(call.request.queryParameters["pattern"].orEmpty())
                    }
                val matches = matches(pattern, db.sql { readDescriptions(userId) })

                call.log.info(
                    "Pattern matched ${matches.count} transactions",
                    "count" to matches.count,
                )
                call.respond(
                    MatchesResponse(matches.count, matches.total, matches.samples.map { it.value })
                )
            }
        }
        .describe {
            summary = "Get the transactions a pattern matches"
            description =
                "Returns how many of the user's transactions a rule pattern matches, ignoring " +
                    "case, out of how many there are, with sample descriptions. Transfers are " +
                    "excluded. The pattern is validated like a rule pattern."
            tag("Auto-tagging")
            parameters {
                query("pattern") {
                    required = true
                    description = "The rule pattern, e.g. COUNTDOWN."
                    schema = JsonSchema(type = JsonType.STRING)
                }
            }
            responses {
                json<MatchesResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
