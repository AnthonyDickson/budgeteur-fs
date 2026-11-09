package budgeteur.feature.rule

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.RULES
import budgeteur.data.requireAll
import budgeteur.data.requireTagIfReferenced
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.json
import budgeteur.shared.log
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.openapi.jsonSchema
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.openapi.describe
import io.ktor.server.routing.put

fun Route.updateRule(db: Db) =
    put("/api/rules/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val rule = call.receiveOrRaise<RuleRequest>().toRule(id)

                db.transaction {
                    requireAll(
                        { requireTagIfReferenced(userId, rule.target.tagId) },
                        { requireUniquePattern(userId, rule) },
                    )
                    val updated =
                        update(RULES)
                            .set(RULES.PATTERN, rule.pattern.value)
                            .set(RULES.TARGET, rule.target.kind.name)
                            .set(RULES.TAG_ID, rule.target.tagId)
                            .where(RULES.ID.eq(id), RULES.USER_ID.eq(userId))
                            .execute()
                    ensure(updated > 0) { DomainError.NotFound("Rule $id not found") }
                }

                call.log.info("Updated rule $id", "ruleId" to id)
                call.respond(rule.toResponse())
            }
        }
        .describe {
            summary = "Update a rule"
            description = "Replaces the rule's pattern and target."
            tag("Rules")
            uuidPath("id")
            requestBody {
                required = true
                schema = jsonSchema<RuleRequest>()
            }
            responses {
                json<RuleResponse>(HttpStatusCode.OK)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.NotFound,
                )
            }
        }
