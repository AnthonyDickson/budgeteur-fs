package budgeteur.feature.rule

import budgeteur.data.readRules
import budgeteur.shared.Db
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe

fun Route.readAllRules(db: Db) =
    get("/api/rules") {
            call.handle {
                val userId = call.userId
                val rules = db.sql { readRules(userId) }

                call.log.info("Returned ${rules.size} rules", "count" to rules.size)
                call.respond(rules.map { it.toResponse() })
            }
        }
        .describe {
            summary = "List all rules"
            description = "Returns all of the user's rules, by pattern."
            tag("Rules")
            responses {
                json<List<RuleResponse>>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized)
            }
        }
