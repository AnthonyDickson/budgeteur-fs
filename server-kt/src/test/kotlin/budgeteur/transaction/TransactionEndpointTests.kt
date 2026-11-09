package budgeteur.transaction

import budgeteur.DEFAULT_TEST_USER
import budgeteur.asUser
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.feature.transaction.TransactionResponse
import budgeteur.feature.transaction.TransactionTagResponse
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.withTestApp
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.http.HttpStatusCode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransactionEndpointTests {
    private val other = "someone-else"

    @Test
    fun `a created transaction is stored as parsed and can be read`() = withTestApp {
        val created = client.createTransaction(transaction("  Groceries ", amount = "-42.5"))

        assertEquals("Groceries", created.description)
        assertEquals("-42.50", created.amount)
        assertEquals("2026-03-08", created.date)
        assertFalse(created.isTransfer)
        assertNull(created.tag)

        val read = client.get("/api/transactions/${created.id}")
        assertEquals(HttpStatusCode.OK, read.status)
        assertEquals(created, read.read<TransactionResponse>())
    }

    @Test
    fun `create reports every invalid field in one response`() = withTestApp { _ ->
        val tagId = client.createTag("Groceries")
        val response =
            client.post("/api/transactions") {
                json(transaction(" ", "12.3.4", "03/08/2026", isTransfer = true, tagId = tagId))
            }

        assertEquals(HttpStatusCode.BadRequest, response.status)
        val lines = response.read<ApiError>().details.lines()
        assertEquals(4, lines.size, "one line per failure: $lines")
        assertTrue("12.3.4" in lines[0])
        assertTrue(lines[1].startsWith("Description cannot"))
        assertTrue("03/08/2026" in lines[2])
        assertEquals("A transfer cannot have a tag", lines[3])
    }

    @Test
    fun `an update replaces the facts and keeps the import hash`() = withTestApp { db ->
        val created = client.createTransaction(transaction("Imported", "12.50"))
        // Imports do not exist yet, so the hash is set directly.
        db.sql { update(TRANSACTIONS).set(TRANSACTIONS.IMPORT_HASH, "row-hash").execute() }

        val response =
            client.put("/api/transactions/${created.id}") {
                json(transaction("Edited", "13.37", "2026-03-09"))
            }

        assertEquals(HttpStatusCode.OK, response.status)
        val updated = response.read<TransactionResponse>()
        assertEquals(
            Triple("Edited", "13.37", "2026-03-09"),
            Triple(updated.description, updated.amount, updated.date),
        )
        assertEquals(created.id, updated.id)
        assertEquals(
            "row-hash",
            db.sql { selectFrom(TRANSACTIONS).fetchSingle().importHash },
        )
    }

    @Test
    fun `another user cannot see, change, or delete a transaction`() = withTestApp {
        val created = client.createTransaction(transaction("Salary", "2500.00"))
        val path = "/api/transactions/${created.id}"

        assertEquals(HttpStatusCode.NotFound, client.get(path) { asUser(other) }.status)
        val hijack =
            client.put(path) {
                json(transaction("Hijacked"))
                asUser(other)
            }
        assertEquals(HttpStatusCode.NotFound, hijack.status)
        assertEquals(HttpStatusCode.NotFound, client.delete(path) { asUser(other) }.status)

        assertEquals("Salary", client.get(path).read<TransactionResponse>().description)
    }

    @Test
    fun `a transaction carries its account's name, and only the user's accounts`() =
        withTestApp { db ->
            val everyday = db.insertAccount(DEFAULT_TEST_USER, "Everyday")
            val savings = db.insertAccount(DEFAULT_TEST_USER, "Savings")

            val created = client.createTransaction(transaction("Coffee", accountId = everyday))
            assertEquals("Everyday", created.accountName)

            val moved =
                client
                    .put("/api/transactions/${created.id}") {
                        json(transaction("Coffee", accountId = savings))
                    }
                    .read<TransactionResponse>()
            assertEquals(savings to "Savings", moved.accountId to moved.accountName)

            val hijack =
                client.post("/api/transactions") {
                    json(transaction("Coffee", accountId = everyday))
                    asUser(other)
                }
            assertEquals(HttpStatusCode.BadRequest, hijack.status)
            assertEquals(
                "Could not find an account with the ID $everyday",
                hijack.read<ApiError>().details,
            )
        }

    @Test
    fun `a transaction cannot use another user's tag`() = withTestApp {
        val tagId = client.createTag("Salary", "Income")

        val response =
            client.post("/api/transactions") {
                json(transaction("Salary", tagId = tagId))
                asUser(other)
            }

        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `the tag source follows the user's edits`() = withTestApp { db ->
        val groceries = client.createTag("Groceries")
        val dining = client.createTag("Dining")
        val created = client.createTransaction(transaction("Countdown", tagId = groceries))
        assertEquals(TransactionTagResponse(groceries, "Manual"), created.tag)

        // Rule tags come from auto-tagging, which the PoC does not have yet.
        db.sql { update(CATEGORISATIONS).set(CATEGORISATIONS.SOURCE, "Rule").execute() }

        suspend fun update(tagId: java.util.UUID?) =
            client
                .put("/api/transactions/${created.id}") {
                    json(transaction("Countdown", "-43.00", tagId = tagId))
                }
                .read<TransactionResponse>()
                .tag

        assertEquals(TransactionTagResponse(groceries, "Rule"), update(groceries))
        assertEquals(TransactionTagResponse(dining, "Manual"), update(dining))
        assertNull(update(null))
    }

    @Test
    fun `marking a transfer replaces the tag and unmarking clears it`() = withTestApp {
        val groceries = client.createTag("Groceries")
        val created = client.createTransaction(transaction("To savings", tagId = groceries))
        val path = "/api/transactions/${created.id}"

        val tagged =
            client.put(path) {
                json(transaction("To savings", isTransfer = true, tagId = groceries))
            }
        assertEquals(HttpStatusCode.BadRequest, tagged.status, "a transfer cannot have a tag")

        val marked =
            client
                .put(path) { json(transaction("To savings", isTransfer = true)) }
                .read<TransactionResponse>()
        assertTrue(marked.isTransfer)
        assertNull(marked.tag)

        val unmarked =
            client.put(path) { json(transaction("To savings")) }.read<TransactionResponse>()
        assertFalse(unmarked.isTransfer)
        assertNull(unmarked.tag)
    }

    @Test
    fun `deleting a tag untags its transactions`() = withTestApp {
        val groceries = client.createTag("Groceries")
        val created = client.createTransaction(transaction("Countdown", tagId = groceries))

        assertEquals(HttpStatusCode.NoContent, client.delete("/api/tags/$groceries").status)

        assertNull(client.get("/api/transactions/${created.id}").read<TransactionResponse>().tag)
    }

    @Test
    fun `a deleted transaction is gone, with its categorisation`() = withTestApp { db ->
        val groceries = client.createTag("Groceries")
        val created = client.createTransaction(transaction("To delete", tagId = groceries))
        val path = "/api/transactions/${created.id}"

        assertEquals(HttpStatusCode.NoContent, client.delete(path).status)
        assertEquals(HttpStatusCode.NotFound, client.get(path).status)
        assertEquals(HttpStatusCode.NotFound, client.delete(path).status)
        assertEquals(0, db.sql { fetchCount(CATEGORISATIONS) })
    }
}
