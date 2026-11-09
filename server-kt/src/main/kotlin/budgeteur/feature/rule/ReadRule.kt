package budgeteur.feature.rule

import arrow.core.raise.context.ensureNotNull
import budgeteur.data.db.tables.references.RULES
import budgeteur.data.toRule
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.openapi.describe

fun Route.readRule(db: Db) =
    get("/api/rules/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val rule =
                    ensureNotNull(
                        db.sql {
                            fetchOne(RULES, RULES.ID.eq(id), RULES.USER_ID.eq(userId))?.toRule()
                        }
                    ) {
                        DomainError.NotFound("Rule $id not found")
                    }

                call.log.info("Returned rule $id", "ruleId" to id)
                call.respond(rule.toResponse())
            }
        }
        .describe {
            summary = "Get a rule by ID"
            description = "Returns a single rule, or 404 if not found."
            tag("Rules")
            uuidPath("id")
            responses {
                json<RuleResponse>(HttpStatusCode.OK)
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
