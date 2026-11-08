package budgeteur.feature.tag

import budgeteur.data.TagCodec
import budgeteur.data.db.tables.references.TAGS
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.Endpoint
import budgeteur.shared.Endpoint.uuidParam
import io.ktor.server.response.respond
import budgeteur.shared.log
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import java.util.UUID
import org.jooq.DSLContext

object ReadTag {
    const val PATH = "/api/tags/{id}"

    private fun get(sql: DSLContext, userId: String, id: UUID): Tag? =
        sql.selectFrom(TAGS)
            .where(TAGS.ID.eq(id), TAGS.USER_ID.eq(userId))
            .fetchOne()
            ?.let(TagCodec::fromRow)

    fun Route.readTag(db: Db) =
        get(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val id = uuidParam(call, "id")
                val tag = db.sql { get(it, userId, id) } ?: raise(DomainError.NotFound("Tag $id not found"))

                call.log.info("Returned tag $id", "tagId" to id)
                call.respond(TagResponse.fromDomain(tag))
            }
        }
}
