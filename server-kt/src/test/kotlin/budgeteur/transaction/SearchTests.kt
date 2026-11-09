package budgeteur.transaction

import arrow.core.raise.context.either
import budgeteur.domain.Money
import budgeteur.feature.transaction.AccountCriterion
import budgeteur.feature.transaction.Cursor
import budgeteur.feature.transaction.Direction
import budgeteur.feature.transaction.PAGE_SIZE
import budgeteur.feature.transaction.Search
import budgeteur.feature.transaction.SearchAccountRequest
import budgeteur.feature.transaction.SearchAmountRequest
import budgeteur.feature.transaction.SearchCriteriaRequest
import budgeteur.feature.transaction.SearchDatesRequest
import budgeteur.feature.transaction.SearchRequest
import budgeteur.feature.transaction.SearchTagRequest
import budgeteur.feature.transaction.TagCriterion
import budgeteur.feature.transaction.page
import budgeteur.feature.transaction.validate
import budgeteur.shared.DomainError
import budgeteur.shared.newId
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

class SearchTests {
    private val anyCriteria =
        SearchCriteriaRequest(
            text = "",
            dates = SearchDatesRequest("AnyTime"),
            account = SearchAccountRequest("Any"),
            tag = SearchTagRequest("Any"),
            amount = SearchAmountRequest("Any"),
        )

    private fun request(
        criteria: SearchCriteriaRequest = anyCriteria,
        today: String = "2026-01-15",
        cursor: String? = null,
    ) = SearchRequest(criteria, today, cursor)

    private fun valid(request: SearchRequest): Pair<Search, Cursor?> = either {
        request.validate()
    }
        .fold({ fail("Expected a valid search, got $it") }, { it })

    private fun search(criteria: SearchCriteriaRequest) = valid(request(criteria)).first

    /** Fails unless validation fails with a message containing each of [parts]. */
    private fun assertInvalid(request: SearchRequest, vararg parts: String) {
        val error = either { request.validate() }.leftOrNull()
        if (error !is DomainError.ValidationFailed)
            fail("Expected a validation failure, got $error")
        parts.forEach { assertTrue(it in error.message, "\"$it\" in \"${error.message}\"") }
    }

    private fun dates(preset: String, from: String? = null, to: String? = null) =
        anyCriteria.copy(dates = SearchDatesRequest(preset, from, to))

    private fun preset(today: String, preset: String): Pair<LocalDate?, LocalDate?> =
        valid(request(dates(preset), today)).first.let { it.from to it.to }

    private fun days(from: String, to: String) = LocalDate.parse(from) to LocalDate.parse(to)

    private fun amount(direction: String, minimum: String? = null, maximum: String? = null) =
        anyCriteria.copy(amount = SearchAmountRequest(direction, minimum, maximum))

    @Test
    fun `no criteria match every transaction`() {
        assertEquals(Search(), search(anyCriteria))
    }

    @Test
    fun `blank text sets no criterion and other text is trimmed`() {
        assertNull(search(anyCriteria.copy(text = "  ")).text)
        assertEquals("count", search(anyCriteria.copy(text = " count ")).text?.value)
    }

    @Test
    fun `text is validated like a rule pattern`() {
        assertInvalid(request(anyCriteria.copy(text = "a".repeat(129))), "too long")
    }

    @Test
    fun `presets resolve from the client's today`() {
        assertEquals(days("2026-01-01", "2026-01-31"), preset("2026-01-15", "ThisMonth"))
        assertEquals(days("2025-12-01", "2025-12-31"), preset("2026-01-15", "LastMonth"))
        assertEquals(days("2026-01-01", "2026-12-31"), preset("2026-01-15", "ThisYear"))
        assertEquals(days("2025-01-01", "2025-12-31"), preset("2026-01-15", "LastYear"))
        assertEquals(null to null, preset("2026-01-15", "AnyTime"))
    }

    @Test
    fun `financial years start on 1 April`() {
        assertEquals(days("2025-04-01", "2026-03-31"), preset("2026-03-31", "ThisFinancialYear"))
        assertEquals(days("2024-04-01", "2025-03-31"), preset("2026-03-31", "LastFinancialYear"))
        assertEquals(days("2026-04-01", "2027-03-31"), preset("2026-04-01", "ThisFinancialYear"))
    }

    @Test
    fun `custom dates are optional and inclusive`() {
        val from = search(dates("Custom", from = "2026-03-08"))
        assertEquals(LocalDate.of(2026, 3, 8) to null, from.from to from.to)
        val oneDay = search(dates("Custom", "2026-03-08", "2026-03-08"))
        assertEquals(days("2026-03-08", "2026-03-08"), oneDay.from to oneDay.to)
    }

    @Test
    fun `invalid dates are reported`() {
        assertInvalid(request(dates("Custom", "2026-03-09", "2026-03-08")), "first day")
        assertInvalid(request(dates("ThisMonth", from = "2026-01-01")), "Only custom dates")
        assertInvalid(request(dates("Fortnight")), "Fortnight")
        assertInvalid(request(dates("Custom", from = "08/03/2026")), "08/03/2026")
        assertInvalid(request(today = "15/01/2026"), "15/01/2026")
    }

    @Test
    fun `account states take an id only for one account`() {
        val id = newId()
        fun account(state: String, id: java.util.UUID? = null) =
            anyCriteria.copy(account = SearchAccountRequest(state, id))

        assertEquals(AccountCriterion.Account(id), search(account("Account", id)).account)
        assertEquals(AccountCriterion.NoAccount, search(account("NoAccount")).account)
        assertInvalid(request(account("Account")), "needs an id")
        assertInvalid(request(account("NoAccount", id)), "takes no id")
        assertInvalid(request(account("Savings")), "Savings")
    }

    @Test
    fun `tag states take an id only for one tag`() {
        val id = newId()
        fun tag(state: String, id: java.util.UUID? = null) =
            anyCriteria.copy(tag = SearchTagRequest(state, id))

        assertEquals(TagCriterion.Tag(id), search(tag("Tag", id)).tag)
        assertEquals(TagCriterion.WithoutTag, search(tag("WithoutTag")).tag)
        assertEquals(TagCriterion.Transfer, search(tag("Transfer")).tag)
        assertInvalid(request(tag("Tag")), "needs an id")
        assertInvalid(request(tag("Dismissed", id)), "takes no id")
        assertInvalid(request(tag("Labelled")), "Labelled")
    }

    @Test
    fun `sizes are money`() {
        val exact = search(amount("Debit", "50", "50.00"))
        assertEquals(Direction.Debit, exact.direction)
        assertEquals(Money(5000) to Money(5000), exact.minimum to exact.maximum)

        assertInvalid(request(amount("Any", minimum = "-1")), "minimum cannot be negative")
        assertInvalid(request(amount("Any", maximum = "1.005")), "maximum can have at most two")
        assertInvalid(request(amount("Any", "200", "50")), "minimum cannot be more than")
        assertInvalid(request(amount("Any", minimum = "1e3")), "1e3")
        assertInvalid(request(amount("Sideways")), "Sideways")
    }

    @Test
    fun `every failure is reported`() {
        val criteria = amount("Sideways").copy(account = SearchAccountRequest("Account"))
        assertInvalid(request(criteria), "Sideways", "needs an id")
    }

    @Test
    fun `a cursor round trips and a malformed one is invalid`() {
        val cursor = Cursor(LocalDate.of(2026, 3, 8), newId())
        assertEquals(cursor, valid(request(cursor = cursor.format())).second)

        listOf("nonsense", "2026-03-08", "2026-03-08_x", "x_${cursor.id}", "${cursor.format()}_1")
            .forEach { assertInvalid(request(cursor = it), "cursor is malformed") }
    }

    @Test
    fun `a page holds up to the page size and a cursor after it`() {
        val cursorOf = { n: Int -> Cursor(LocalDate.of(2026, 3, 8), java.util.UUID(0, n.toLong())) }

        val (full, next) = page((1..PAGE_SIZE + 1).toList(), cursorOf)
        assertEquals((1..PAGE_SIZE).toList(), full)
        assertEquals(cursorOf(PAGE_SIZE), next)

        val (last, none) = page((1..PAGE_SIZE).toList(), cursorOf)
        assertEquals(PAGE_SIZE, last.size)
        assertNull(none)
    }
}
