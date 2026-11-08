package budgeteur.feature.tag

import budgeteur.data.TagCodec
import budgeteur.data.db.tables.references.TAGS
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.Endpoint
import io.ktor.server.response.respond
import budgeteur.shared.log
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import org.jooq.DSLContext

object ReadAllTags {
    const val PATH = "/api/tags"

    private fun getAll(sql: DSLContext, userId: String): List<Tag> =
        sql.selectFrom(TAGS).where(TAGS.USER_ID.eq(userId)).fetch().map(TagCodec::fromRow)

    fun Route.readAllTags(db: Db) =
        get(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val tags = db.sql { getAll(it, userId) }

                call.log.info("Returned ${tags.size} tags", "count" to tags.size)
                call.respond(tags.map(TagResponse::fromDomain))
            }
        }
}
