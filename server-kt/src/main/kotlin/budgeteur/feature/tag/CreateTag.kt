package budgeteur.feature.tag

import arrow.core.Either
import arrow.core.raise.either
import arrow.core.raise.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.Constraints.requireAll
import budgeteur.data.TagCodec
import budgeteur.data.db.tables.references.TAGS
import budgeteur.domain.Tag
import budgeteur.domain.TagName
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.Endpoint
import budgeteur.shared.Json
import budgeteur.shared.log
import budgeteur.shared.uuidV7
import io.ktor.http.HttpStatusCode
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import org.jooq.DSLContext

object CreateTag {
    const val PATH = "/api/tags"

    /** The `UNIQUE (user_id, name)` constraint. */
    private fun requireNameIsUnique(sql: DSLContext, userId: String, name: TagName): Either<ConstraintError, Unit> =
        either {
            val taken = sql.fetchExists(TAGS, TAGS.USER_ID.eq(userId), TAGS.NAME.eq(name.value))
            ensure(!taken) { ConstraintError("A tag with the name '${name.value}' already exists") }
        }

    private fun insert(sql: DSLContext, userId: String, tag: Tag) {
        sql.insertInto(TAGS).set(TagCodec.toRow(tag, userId)).execute()
    }

    fun Route.createTag(db: Db) =
        post(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val request = Json.read<TagRequest>(call).bind()
                val tag = parseTag(uuidV7(), request)

                requireAll(db.sql { requireNameIsUnique(it, userId, tag.name) })
                db.sql { insert(it, userId, tag) }

                call.log.info("Created tag ${tag.id}", "tagId" to tag.id)
                Json.write(call, TagResponse.fromDomain(tag), HttpStatusCode.Created)
            }
        }
}
