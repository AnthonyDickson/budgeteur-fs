package budgeteur.auth

import budgeteur.feature.auth.resolveReturnUrl
import kotlin.test.Test
import kotlin.test.assertEquals

class ReturnUrlTests {
    /** The client's origin in development, which differs from the server's. */
    private val baseUrl = "http://localhost:5173/"

    @Test
    fun `a login returns to the page the user was on`() {
        val page = "/balance-sheet/accounts/1?from=2026-01-01#x"
        assertEquals("http://localhost:5173$page", resolveReturnUrl(baseUrl, page))
    }

    @Test
    fun `without a page, a login returns to the configured URL`() {
        assertEquals(baseUrl, resolveReturnUrl(baseUrl, null))
        assertEquals(baseUrl, resolveReturnUrl(baseUrl, ""))
    }

    @Test
    fun `a login never returns to another site`() {
        listOf(
                "https://evil.example.com/",
                "//evil.example.com/",
                "/\\evil.example.com/",
                "javascript:alert(1)",
                "transactions",
                "/transactions\r\nSet-Cookie: x=1",
            )
            .forEach { assertEquals(baseUrl, resolveReturnUrl(baseUrl, it), it) }
    }
}
