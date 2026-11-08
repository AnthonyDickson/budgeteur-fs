package budgeteur.shared

import budgeteur.data.db.tables.records.TagsRecord
import budgeteur.data.db.tables.references.TAGS
import budgeteur.withTempDb
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.jooq.DSLContext

class DbTests {
    private fun DSLContext.nameTaken() =
        fetchExists(TAGS, TAGS.USER_ID.eq("user"), TAGS.NAME.eq("Rent"))

    private fun DSLContext.insertRent() =
        insertInto(TAGS).set(TagsRecord(newId(), "user", "Rent", "Red", "Expense")).execute()

    @Test
    fun `a check in a transaction sees the write of a transaction that began first`() =
        withTempDb { db ->
            runBlocking {
                val firstChecked = CompletableDeferred<Unit>()
                val first = async {
                    db.transaction {
                        check(!nameTaken())
                        firstChecked.complete(Unit)
                        // Give the second transaction time to try to begin.
                        Thread.sleep(200)
                        insertRent()
                    }
                }
                firstChecked.await()
                val second = db.transaction {
                    if (nameTaken()) "taken" else "inserted".also { insertRent() }
                }

                first.await()
                assertEquals("taken", second)
            }
        }
}
