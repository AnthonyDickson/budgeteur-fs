package budgeteur.feature.transaction

import budgeteur.domain.formatCalendarDate
import budgeteur.shared.DATE_FORMAT
import budgeteur.shared.Db
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
@JsonSchema.Description("A page of a search's matches.")
data class SearchResponse(
    @JsonSchema.Description("Up to 100 matches, newest first, then by id.")
    val transactions: List<TransactionResponse>,
    @JsonSchema.Description(
        "Where the next page starts, to send with the same criteria, or none on the last page."
    )
    val cursor: String?,
    @JsonSchema.Description("The dates criterion's first day, with a preset resolved, or none.")
    @JsonSchema.Format(DATE_FORMAT)
    val from: String?,
    @JsonSchema.Description("The dates criterion's last day, with a preset resolved, or none.")
    @JsonSchema.Format(DATE_FORMAT)
    val to: String?,
)

fun Route.searchTransactions(db: Db) =
    post("/api/transactions/search") {
            call.handle {
                val userId = call.userId
                val (search, after) = call.receiveOrRaise<SearchRequest>().validate()
                val (matches, next) = db.sql { searchTransactions(userId, search, after) }

                // The criteria are financial data, so only the count is logged.
                call.log.info(
                    "Returned ${matches.size} matching transactions",
                    "count" to matches.size,
                )
                call.respond(
                    SearchResponse(
                        transactions = matches.map { it.toResponse() },
                        cursor = next?.format(),
                        from = search.from?.formatCalendarDate(),
                        to = search.to?.formatCalendarDate(),
                    )
                )
            }
        }
        .describe {
            summary = "Search transactions"
            description =
                "Returns a page of the user's transactions that meet every criterion, newest " +
                    "first, and a cursor for the next page. Date presets are resolved from the " +
                    "client's today, and the response carries the resolved days. A POST so the " +
                    "criteria are a typed body; it changes nothing."
            tag("Transactions")
            requestBody {
                required = true
                schema = jsonSchema<SearchRequest>()
            }
            responses {
                json<SearchResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
