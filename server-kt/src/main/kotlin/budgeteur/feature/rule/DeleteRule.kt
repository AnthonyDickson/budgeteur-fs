package budgeteur.feature.rule

import arrow.core.raise.context.ensure
import budgeteur.data.db.tables.references.RULES
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.errors
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.noContent
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import budgeteur.shared.uuidPath
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.openapi.describe

fun Route.deleteRule(db: Db) =
    delete("/api/rules/{id}") {
            call.handle {
                val userId = call.userId
                val id = call.uuidParam("id")
                val deleted = db.sql {
                    deleteFrom(RULES).where(RULES.ID.eq(id), RULES.USER_ID.eq(userId)).execute()
                }
                ensure(deleted > 0) { DomainError.NotFound("Rule $id not found") }

                call.log.info("Deleted rule $id", "ruleId" to id)
                call.respond(HttpStatusCode.NoContent)
            }
        }
        .describe {
            summary = "Delete a rule"
            description = "Permanently removes a rule. Returns 204 on success."
            tag("Rules")
            uuidPath("id")
            responses {
                noContent()
                errors(HttpStatusCode.Unauthorized, HttpStatusCode.NotFound)
            }
        }
