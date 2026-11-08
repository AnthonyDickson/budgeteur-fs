package budgeteur.feature.tag

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.requireAll
import budgeteur.data.toRecord
import budgeteur.domain.Tag
import budgeteur.domain.TagName
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
import org.jooq.DSLContext

/** The `UNIQUE (user_id, name)` constraint. */
context(_: Raise<ConstraintError>)
private fun DSLContext.requireUniqueName(userId: String, name: TagName) =
    ensure(!fetchExists(TAGS, TAGS.USER_ID.eq(userId), TAGS.NAME.eq(name.value))) {
        ConstraintError("A tag with the name '${name.value}' already exists")
    }

private fun DSLContext.insertTag(userId: String, tag: Tag) {
    insertInto(TAGS).set(tag.toRecord(userId)).execute()
}

fun Route.createTag(db: Db) =
    post("/api/tags") {
            call.handle {
                val userId = call.userId
                val tag = call.receiveOrRaise<TagRequest>().toTag(newId())

                db.transaction {
                    requireAll({ requireUniqueName(userId, tag.name) })
                    insertTag(userId, tag)
                }

                call.log.info("Created tag ${tag.id}", "tagId" to tag.id)
                call.respond(HttpStatusCode.Created, tag.toResponse())
            }
        }
        .describe {
            summary = "Create a tag"
            description = "Creates a new tag and returns it with status 201."
            tag("Tags")
            requestBody {
                required = true
                schema = jsonSchema<TagRequest>()
            }
            responses {
                json<TagResponse>(HttpStatusCode.Created)
                errors(
                    HttpStatusCode.BadRequest,
                    HttpStatusCode.Unauthorized,
                    HttpStatusCode.Conflict,
                )
            }
        }
