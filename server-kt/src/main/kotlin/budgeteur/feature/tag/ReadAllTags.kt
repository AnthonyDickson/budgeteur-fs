package budgeteur.feature.tag

import budgeteur.data.TagCodec
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.Endpoint
import budgeteur.shared.Json
import budgeteur.shared.log
import budgeteur.shared.query
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import java.sql.Connection

object ReadAllTags {
    const val PATH = "/api/tags"

    private fun getAll(c: Connection, userId: String): List<Tag> =
        c.query("SELECT ${TagCodec.COLUMNS} FROM Tags WHERE UserId = ?", userId, row = TagCodec::fromRow)

    fun Route.readAllTags(db: Db) =
        get(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val tags = db.run { getAll(it, userId) }

                call.log.info("Returned ${tags.size} tags", "count" to tags.size)
                Json.write(call, tags.map(TagResponse::fromDomain))
            }
        }
}
