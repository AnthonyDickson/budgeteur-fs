package budgeteur.transaction

import budgeteur.data.db.tables.records.AccountsRecord
import budgeteur.data.db.tables.references.ACCOUNTS
import budgeteur.feature.tag.TagResponse
import budgeteur.feature.transaction.TransactionRequest
import budgeteur.feature.transaction.TransactionResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.Db
import budgeteur.shared.apiJson
import budgeteur.shared.newId
import io.ktor.client.HttpClient
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.post
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import java.util.UUID
import kotlin.test.assertEquals

fun transaction(
    description: String,
    amount: String = "-1.00",
    date: String = "2026-03-08",
    isTransfer: Boolean = false,
    tagId: UUID? = null,
    accountId: UUID? = null,
) = TransactionRequest(amount, description, date, isTransfer, tagId, accountId)

fun HttpRequestBuilder.json(request: TransactionRequest) = json(apiJson.encodeToString(request))

suspend fun HttpClient.createTransaction(
    request: TransactionRequest,
    configure: HttpRequestBuilder.() -> Unit = {},
): TransactionResponse {
    val response =
        post("/api/transactions") {
            json(request)
            configure()
        }
    assertEquals(HttpStatusCode.Created, response.status, response.bodyAsText())
    return response.read()
}

suspend fun HttpClient.createTag(name: String, kind: String = "Expense"): UUID =
    post("/api/tags") { json("""{"name": "$name", "color": "Green", "kind": "$kind"}""") }
        .read<TagResponse>()
        .id

/** The PoC has no accounts slice yet, so tests write accounts directly. */
suspend fun Db.insertAccount(userId: String, name: String): UUID {
    val id = newId()
    sql {
        insertInto(ACCOUNTS)
            .set(
                AccountsRecord(
                    id = id,
                    userId = userId,
                    number = null,
                    name = name,
                    term = "Current",
                    closedOn = null,
                )
            )
            .execute()
    }
    return id
}
