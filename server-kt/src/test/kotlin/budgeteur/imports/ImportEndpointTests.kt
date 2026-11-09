package budgeteur.imports

import budgeteur.asUser
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.data.db.tables.references.CATEGORISATIONS
import budgeteur.data.db.tables.references.TRANSACTIONS
import budgeteur.feature.account.AccountBalanceResponse
import budgeteur.feature.account.AccountResponse
import budgeteur.feature.imports.CreatedAccountResponse
import budgeteur.feature.imports.Formats
import budgeteur.feature.imports.IMPORT_BODY_LIMIT
import budgeteur.feature.imports.ImportFileRequest
import budgeteur.feature.imports.ImportRequest
import budgeteur.feature.imports.ImportResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.ApiError
import budgeteur.shared.Db
import budgeteur.shared.apiJson
import budgeteur.transaction.createTag
import budgeteur.withTestApp
import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ImportEndpointTests {
    private fun file(name: String) = ImportFileRequest(name, fixture(name))

    private suspend fun HttpClient.post(
        files: List<ImportFileRequest>,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): HttpResponse =
        post("/api/imports") {
            json(apiJson.encodeToString(ImportRequest(files)))
            configure()
        }

    private suspend fun HttpClient.import(
        vararg files: ImportFileRequest,
        configure: HttpRequestBuilder.() -> Unit = {},
    ): ImportResponse {
        val response = post(files.toList(), configure)
        assertEquals(HttpStatusCode.OK, response.status, response.bodyAsText())
        return response.read()
    }

    private suspend fun HttpClient.accounts() = get("/api/accounts").read<List<AccountResponse>>()

    /** The user's transactions as (account id, is transfer, is tagged), straight from the table. */
    private suspend fun Db.transactions(user: String = "test-user") = sql {
        select(TRANSACTIONS.ACCOUNT_ID, CATEGORISATIONS.KIND)
            .from(TRANSACTIONS)
            .leftJoin(CATEGORISATIONS)
            .on(CATEGORISATIONS.TRANSACTION_ID.eq(TRANSACTIONS.ID))
            .where(TRANSACTIONS.USER_ID.eq(user))
            .fetch { it.value1() to it.value2() }
    }

    /** A Kiwibank statement of savings rows, one per day of March. */
    private fun kiwibank(vararg rows: Pair<Int, String>) =
        ImportFileRequest(
            "savings.csv",
            (listOf(Formats.kiwibank.header) +
                    rows.map { (day, balance) ->
                        val date = "2026-03-%02d".format(day)
                        "12-3456-0789012-01,$date,$date,INTEREST,INTEREST CREDIT,,,,,,,,,1.00," +
                            balance
                    })
                .joinToString("\n"),
        )

    @Test
    fun `related statements import with transfers and tags`() = withTestApp { db ->
        val dining = client.createTag("Dining")
        val rule =
            client.post("/api/rules") {
                json("""{"pattern": "harbour cafe", "target": "Tag", "tagId": "$dining"}""")
            }
        assertEquals(HttpStatusCode.Created, rule.status)

        val result = client.import(file("KiwibankChequing.csv"), file("KiwibankSavings.csv"))

        assertEquals(
            ImportResponse(
                imported = 218,
                skippedDuplicates = 0,
                transfers = 40,
                taggedByRules = 26,
                accountsCreated = result.accountsCreated,
            ),
            result,
            "every row, both sides of each transfer, the rule's matches",
        )
        assertEquals(
            listOf(
                "12-3456-0789012-000" to "12-3456-0789012-000",
                "12-3456-0789012-001" to "12-3456-0789012-001",
            ),
            result.accountsCreated.map { it.name to it.number },
            "an account per statement, named after its number",
        )

        // Then: transactions carry their account, and transfers have no tag.
        val ids = result.accountsCreated.associate { it.id to it.number }
        val transactions = db.transactions()
        assertEquals(
            mapOf<String?, Int>("12-3456-0789012-000" to 192, "12-3456-0789012-001" to 26),
            transactions.groupingBy { (accountId, _) -> accountId?.let(ids::get) }.eachCount(),
        )
        assertEquals(40, transactions.count { it.second == "Transfer" })

        // Then: each account's current balance is its statement's closing balance.
        assertEquals(
            listOf(
                "12-3456-0789012-000" to "1053.99",
                "12-3456-0789012-001" to "5596.99",
            ),
            client.accounts().map { it.number to it.balance?.balance },
        )
    }

    @Test
    fun `a repeated import skips every row`() = withTestApp { db ->
        client.import(file("KiwibankChequing.csv"))

        val again =
            client.import(
                file("KiwibankChequing.csv"),
                // The same statement twice in one request.
                file("AsbCard.csv"),
                file("AsbCard.csv"),
            )

        assertEquals(8, again.imported, "only the card's rows, once")
        assertEquals(200, again.skippedDuplicates, "192 + 8 repeated")
        assertEquals(
            listOf("XXXX-XXXX-XXXX-0000 (Visa Light)"),
            again.accountsCreated.map { it.name },
            "the card's account is named with its product",
        )
        assertEquals(200, db.transactions().size, "no duplicates were written")
    }

    @Test
    fun `a file that cannot be read fails the whole request`() = withTestApp { db ->
        val broken =
            ImportFileRequest(
                "broken.csv",
                Formats.kiwibank.header +
                    "\n12-3456-0789012-01,2026-03-01,2026-03-01,X,Y,,,,,,,,,ten,1.00",
            )

        val response =
            client.post(
                listOf(file("KiwibankChequing.csv"), broken, ImportFileRequest("notes.txt", "hi"))
            )

        assertEquals(HttpStatusCode.BadRequest, response.status)
        val details = response.read<ApiError>().details
        assertContains(details, "broken.csv line 2: Amount \"ten\" is not an amount")
        assertContains(details, "notes.txt: matches no known format")
        assertTrue(db.transactions().isEmpty(), "nothing from the good file was written")
        assertTrue(client.accounts().isEmpty(), "no account was created")
    }

    @Test
    fun `an import needs a file`() = withTestApp {
        assertEquals(HttpStatusCode.BadRequest, client.post(emptyList()).status)
    }

    @Test
    fun `an import may be larger than the default body limit`() = withTestApp {
        val rows = (1..20_000).map { "Account number padding row $it" }.joinToString("\n")
        val response = client.post(listOf(ImportFileRequest("large.csv", rows)))
        assertTrue(rows.length in 65_536..IMPORT_BODY_LIMIT)
        assertEquals(HttpStatusCode.BadRequest, response.status, "read, not refused")
    }

    @Test
    fun `an older statement does not change the current balance`() = withTestApp {
        client.import(kiwibank(10 to "100", 11 to "101"))
        client.import(kiwibank(1 to "50", 2 to "51"))

        assertEquals(
            listOf(AccountBalanceResponse("101.00", "2026-03-11")),
            client.accounts().map { it.balance },
        )
    }

    @Test
    fun `an existing account is found by its number`() = withTestApp { db ->
        val everyday =
            client
                .post("/api/accounts") {
                    json(
                        """{"name": "Everyday", "number": "12-3456-789012-00", "term": "Current"}"""
                    )
                }
                .read<AccountResponse>()

        val result = client.import(file("KiwibankChequing.csv"))

        assertEquals(listOf<CreatedAccountResponse>(), result.accountsCreated)
        assertTrue(db.transactions().all { it.first == everyday.id }, "rows join the account")
    }

    @Test
    fun `an import is scoped to the caller`() = withTestApp { db ->
        val other = "other-user"
        client.import(file("KiwibankSavings.csv"))

        // Another user's hashes and accounts do not count.
        val result = client.import(file("KiwibankSavings.csv")) { asUser(other) }

        assertEquals(26, result.imported, "nothing is a duplicate")
        assertEquals(0, result.transfers, "chequing is not their account")
        assertEquals(1, result.accountsCreated.size, "they get their own account")
        assertEquals(26, db.transactions().size, "the first user still has 26")
        assertEquals(
            1,
            db.sql { fetchCount(ACCOUNTS, ACCOUNTS.USER_ID.eq(other)) },
            "their account is theirs",
        )
    }
}
