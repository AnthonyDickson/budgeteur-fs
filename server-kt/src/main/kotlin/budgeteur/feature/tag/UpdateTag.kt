package budgeteur.feature.tag

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.db.tables.references.TAGS
import budgeteur.data.requireAll
import budgeteur.domain.Tag
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.handle
import budgeteur.shared.log
import budgeteur.shared.receiveOrRaise
import budgeteur.shared.userId
import budgeteur.shared.uuidParam
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.put
import org.jooq.DSLContext

/** The `UNIQUE (user_id, name)` constraint, ignoring the tag being updated. */
context(_: Raise<ConstraintError>)
private fun DSLContext.requireUniqueName(userId: String, tag: Tag) =
    ensure(
        !fetchExists(
            TAGS,
            TAGS.USER_ID.eq(userId),
            TAGS.NAME.eq(tag.name.value),
            TAGS.ID.ne(tag.id),
        )
    ) {
        ConstraintError("A tag with the name '${tag.name.value}' already exists")
    }

/** Returns false when the user has no tag with the id. */
private fun DSLContext.updateTag(userId: String, tag: Tag): Boolean =
    update(TAGS)
        .set(TAGS.NAME, tag.name.value)
        .set(TAGS.COLOR, tag.color.name)
        .set(TAGS.KIND, tag.kind.name)
        .where(TAGS.ID.eq(tag.id), TAGS.USER_ID.eq(userId))
        .execute() > 0

fun Route.updateTag(db: Db) =
    put("/api/tags/{id}") {
        call.handle {
            val userId = call.userId
            val id = call.uuidParam("id")
            val tag = call.receiveOrRaise<TagRequest>().toTag(id)

            db.transaction {
                requireAll({ requireUniqueName(userId, tag) })
                ensure(updateTag(userId, tag)) { DomainError.NotFound("Tag $id not found") }
            }

            call.log.info("Updated tag $id", "tagId" to id)
            call.respond(tag.toResponse())
        }
    }
