package budgeteur.feature.tag

import arrow.core.Either
import arrow.core.raise.either
import arrow.core.raise.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.Constraints.requireAll
import budgeteur.data.db.tables.references.TAGS
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.Endpoint
import budgeteur.shared.Endpoint.uuidParam
import budgeteur.shared.Json
import budgeteur.shared.log
import io.ktor.server.routing.Route
import io.ktor.server.routing.put
import org.jooq.DSLContext

object UpdateTag {
    const val PATH = "/api/tags/{id}"

    /** The `UNIQUE (user_id, name)` constraint, ignoring the tag being updated. */
    private fun requireNameIsUnique(sql: DSLContext, userId: String, tag: Tag): Either<ConstraintError, Unit> =
        either {
            val taken = sql.fetchExists(TAGS, TAGS.USER_ID.eq(userId), TAGS.NAME.eq(tag.name.value), TAGS.ID.ne(tag.id))
            ensure(!taken) { ConstraintError("A tag with the name '${tag.name.value}' already exists") }
        }

    /** Returns false when the user has no tag with the id. */
    private fun update(sql: DSLContext, userId: String, tag: Tag): Boolean =
        sql.update(TAGS)
            .set(TAGS.NAME, tag.name.value)
            .set(TAGS.COLOR, tag.color.name)
            .set(TAGS.KIND, tag.kind.name)
            .where(TAGS.ID.eq(tag.id), TAGS.USER_ID.eq(userId))
            .execute() > 0

    fun Route.updateTag(db: Db) =
        put(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val id = uuidParam(call, "id")
                val request = Json.read<TagRequest>(call).bind()
                val tag = parseTag(id, request)

                requireAll(db.sql { requireNameIsUnique(it, userId, tag) })
                ensure(db.sql { update(it, userId, tag) }) { DomainError.NotFound("Tag $id not found") }

                call.log.info("Updated tag $id", "tagId" to id)
                Json.write(call, TagResponse.fromDomain(tag))
            }
        }
}
