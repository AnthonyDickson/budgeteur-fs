package budgeteur.feature.tag

import budgeteur.feature.tag.CreateTag.createTag
import budgeteur.feature.tag.DeleteTag.deleteTag
import budgeteur.feature.tag.ReadAllTags.readAllTags
import budgeteur.feature.tag.ReadTag.readTag
import budgeteur.feature.tag.UpdateTag.updateTag
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
