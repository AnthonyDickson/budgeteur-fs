package budgeteur.transaction

import budgeteur.feature.account.AccountResponse
import budgeteur.feature.tag.TagResponse
import budgeteur.feature.transaction.TransactionRequest
import budgeteur.feature.transaction.TransactionResponse
import budgeteur.json
import budgeteur.read
import budgeteur.shared.apiJson
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

suspend fun HttpClient.createAccount(name: String): UUID =
    post("/api/accounts") { json("""{"name": "$name", "term": "Current"}""") }
        .read<AccountResponse>()
        .id
