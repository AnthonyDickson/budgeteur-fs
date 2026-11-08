package budgeteur.feature.tag

import budgeteur.data.TagCodec
import budgeteur.domain.Tag
import budgeteur.shared.Auth
import budgeteur.shared.Db
import budgeteur.shared.DomainError
import budgeteur.shared.Endpoint
import budgeteur.shared.Endpoint.uuidParam
import budgeteur.shared.Json
import budgeteur.shared.log
import budgeteur.shared.query
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import java.sql.Connection
import java.util.UUID

object ReadTag {
    const val PATH = "/api/tags/{id}"

    private fun get(c: Connection, userId: String, id: UUID): Tag? =
        c.query("SELECT ${TagCodec.COLUMNS} FROM Tags WHERE Id = ? AND UserId = ?", id, userId, row = TagCodec::fromRow)
            .singleOrNull()

    fun Route.readTag(db: Db) =
        get(PATH) {
            Endpoint.handle(call) {
                val userId = Auth.userId(call).bind()
                val id = uuidParam(call, "id")
                val tag = db.run { get(it, userId, id) } ?: raise(DomainError.NotFound("Tag $id not found"))

                call.log.info("Returned tag $id", "tagId" to id)
                Json.write(call, TagResponse.fromDomain(tag))
            }
        }
}
