package budgeteur.feature.rule

import budgeteur.data.db.tables.references.RULES
import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.data.toRecord
import budgeteur.shared.Db
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.newId
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.post

fun Route.createRule(db: Db) =
    post("/api/rules") {
            call.handle {
                val userId = call.userId
                val rule = call.receiveOrRaise<RuleRequest>().toRule(newId())

                db.transaction {
                    requireAll(
                        { requireTagIfReferenced(userId, rule.target.tagId) },
                        { requireUniquePattern(userId, rule) },
                    )
                    insertInto(RULES).set(rule.toRecord(userId)).execute()
                }

                call.log.info("Created rule ${rule.id}", "ruleId" to rule.id)
                call.respond(HttpStatusCode.Created, rule.toResponse())
            }
        }
        .describe {
            summary = "Create a rule"
            description = "Creates a new rule and returns it with status 201."
            tag("Rules")
            requestBody {
                required = true
                schema = jsonSchema<RuleRequest>()
            }
            responses {
                json<RuleResponse>(HttpStatusCode.Created)
                errors(HttpStatusCode.BadRequest, HttpStatusCode.Unauthorized)
            }
        }
