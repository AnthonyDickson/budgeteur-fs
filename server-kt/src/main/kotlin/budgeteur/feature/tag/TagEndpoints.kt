package budgeteur.feature.tag

import budgeteur.shared.Db
import io.ktor.server.routing.Route

/** The slice's routes. Shared by the server and the test host so both route the same handlers. */
fun Route.tagEndpoints(db: Db) {
    createTag(db)
    readTag(db)
    readAllTags(db)
    updateTag(db)
    deleteTag(db)
}
