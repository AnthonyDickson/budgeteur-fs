package budgeteur.shared

import budgeteur.TEST_SCALAR_CLIENT
import budgeteur.domain.TagColor
import budgeteur.domain.TagName
import budgeteur.withTestApp
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class ApiDocsTests {
    private fun JsonElement.at(vararg keys: String): JsonElement =
        keys.fold(this) { element, key -> element.jsonObject.getValue(key) }

    private fun JsonElement.strings(): List<String> = jsonArray.map { it.jsonPrimitive.content }

    private fun withDocument(block: (JsonObject) -> Unit) = withTestApp {
        val response = client.get(OPENAPI_PATH)
        assertEquals(HttpStatusCode.OK, response.status)
        block(Json.parseToJsonElement(response.bodyAsText()).jsonObject)
    }

    @Test
    fun `the document covers the API endpoints only`() = withDocument { doc ->
        // Not the login redirects, the docs themselves, the Development-only
        // endpoints, or the JSON 404 for unknown paths.
        assertEquals(
            setOf(
                "/api/status",
                "/api/tags",
                "/api/tags/{id}",
                "/api/transactions",
                "/api/transactions/search",
                "/api/transactions/{id}",
                "/api/accounts",
                "/api/accounts/{id}",
                "/api/accounts/{id}/close-date",
                "/api/accounts/{id}/observations",
                "/api/accounts/{id}/observations/{asOf}",
                "/api/balance-sheet",
                "/api/balance-sheet/items",
                "/api/balance-sheet/items/{id}",
                "/api/balance-sheet/items/{id}/close-date",
                "/api/balance-sheet/items/{id}/observations",
                "/api/balance-sheet/items/{id}/observations/{asOf}",
                "/api/rules",
                "/api/rules/{id}",
                "/api/auto-tag",
                "/api/auto-tag/matches",
                "/api/imports",
            ),
            doc.at("paths").jsonObject.keys,
        )
    }

    @Test
    fun `API endpoints accept the session cookie or a token from the provider`() =
        withDocument { doc ->
            val security = doc.at("paths", "/api/tags", "post", "security").jsonArray
            assertEquals(
                listOf(setOf("session"), setOf("bearer")),
                security.map { it.jsonObject.keys },
            )
            assertEquals(null, doc.at("paths", "/api/status", "get").jsonObject["security"])

            val schemes = doc.at("components", "securitySchemes")
            assertEquals("budgeteur_session", schemes.at("session", "name").jsonPrimitive.content)
            assertEquals("cookie", schemes.at("session", "in").jsonPrimitive.content)
            val flow = schemes.at("bearer", "flows", "authorizationCode")
            assertEquals(
                "https://provider.test/authorize",
                flow.at("authorizationUrl").jsonPrimitive.content,
            )
            assertEquals("https://provider.test/token", flow.at("tokenUrl").jsonPrimitive.content)
        }

    @Test
    fun `schemas follow the domain's rules`() = withDocument { doc ->
        val schemas = doc.at("components", "schemas")
        // One schema per type, however many places it appears.
        assertEquals(
            setOf(
                "ApiError",
                "DatabaseHealth",
                "StatusResponse",
                "TagRequest",
                "TagResponse",
                "TransactionRequest",
                "TransactionResponse",
                "TransactionTagResponse",
                "SearchRequest",
                "SearchCriteriaRequest",
                "SearchDatesRequest",
                "SearchAccountRequest",
                "SearchTagRequest",
                "SearchAmountRequest",
                "SearchResponse",
                "CreateAccountRequest",
                "UpdateAccountRequest",
                "CloseAccountRequest",
                "BalanceEntryRequest",
                "AccountResponse",
                "AccountBalanceResponse",
                "TransactionsAfterCloseResponse",
                "BalanceSheetResponse",
                "BalanceSheetItemResponse",
                "AccountLineResponse",
                "UnknownBalanceResponse",
                "ClosedAccountResponse",
                "LateTransactionsResponse",
                "CreateBalanceSheetItemRequest",
                "UpdateBalanceSheetItemRequest",
                "CloseBalanceSheetItemRequest",
                "ItemObservationRequest",
                "ItemObservationResponse",
                "RuleRequest",
                "RuleResponse",
                "RunAutoTagRequest",
                "RunAutoTagResponse",
                "MatchesResponse",
                "ImportFileRequest",
                "ImportRequest",
                "CreatedAccountResponse",
                "ImportResponse",
            ),
            schemas.jsonObject.keys,
        )

        val request = schemas.at("TagRequest")
        assertEquals(listOf("name", "color", "kind"), request.at("required").strings())
        assertEquals(
            TagName.MAX_LENGTH,
            request.at("properties", "name", "maxLength").jsonPrimitive.content.toInt(),
        )
        assertEquals(
            TagColor.entries.map { it.name },
            request.at("properties", "color", "enum").strings(),
        )
        assertEquals(
            listOf("Income", "Expense"),
            schemas.at("TagResponse", "properties", "kind", "enum").strings(),
        )
        assertEquals(
            "uuid",
            schemas.at("TagResponse", "properties", "id", "format").jsonPrimitive.content,
        )
        assertEquals(
            "uuid",
            doc.at("paths", "/api/tags/{id}", "get")
                .jsonObject
                .getValue("parameters")
                .jsonArray
                .single()
                .at("schema", "format")
                .jsonPrimitive
                .content,
        )
    }

    @Test
    fun `amounts and dates are documented as the strings they are`() = withDocument { doc ->
        val transaction = doc.at("components", "schemas", "TransactionResponse", "properties")
        assertEquals("string", transaction.at("amount", "type").jsonPrimitive.content)
        assertEquals(MONEY_PATTERN, transaction.at("amount", "pattern").jsonPrimitive.content)
        assertEquals(DATE_FORMAT, transaction.at("date", "format").jsonPrimitive.content)
        assertEquals(
            listOf("Manual", "Accepted", "Rule", "Detected"),
            doc.at(
                    "components",
                    "schemas",
                    "TransactionTagResponse",
                    "properties",
                    "source",
                    "enum",
                )
                .strings(),
        )
        val parameters =
            doc.at("paths", "/api/accounts/{id}/observations/{asOf}", "delete")
                .jsonObject
                .getValue("parameters")
                .jsonArray
                .associate {
                    it.at("name").jsonPrimitive.content to
                        it.at("schema", "format").jsonPrimitive.content
                }
        assertEquals(mapOf("id" to "uuid", "asOf" to DATE_FORMAT), parameters)
    }

    @Test
    fun `Scalar logs in with the docs client`() = withTestApp {
        val page = client.get(SCALAR_PATH).bodyAsText()
        assertContains(page, "\"x-scalar-client-id\":\"$TEST_SCALAR_CLIENT\"")
        assertContains(page, "\"url\":\"$OPENAPI_PATH\"")
    }
}
