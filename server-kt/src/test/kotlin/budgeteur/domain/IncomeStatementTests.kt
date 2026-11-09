package budgeteur.domain

import java.math.BigDecimal
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class IncomeStatementTests {
    private fun tag(name: String, kind: TagKind) =
        Tag(UUID.randomUUID(), TagName.unsafe(name), TagColor.Green, kind)

    private val period = Period(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 31))

    private fun entry(dollars: Long, tag: Tag?) =
        Entry(LocalDate.of(2026, 10, 1), Money(dollars * 100), tag)

    private fun compute(vararg entries: Entry) = IncomeStatement.compute(period, entries.toList())

    private fun List<StatementLine>.amounts() = map { it.tag?.id to it.amount }

    private fun dollars(amount: Long) = Money(amount * 100)

    @Test
    fun `an empty period has no lines and zero totals`() {
        val statement = compute()
        assertTrue(statement.incomeLines.isEmpty() && statement.expenseLines.isEmpty())
        assertEquals(Money.ZERO, statement.netIncome)
    }

    @Test
    fun `a refund reduces its expense tag rather than counting as income`() {
        val groceries = tag("Groceries", TagKind.Expense)
        val statement = compute(entry(-100, groceries), entry(30, groceries))
        assertEquals(listOf(groceries.id to dollars(70)), statement.expenseLines.amounts())
        assertTrue(statement.incomeLines.isEmpty(), "a refund is not income")
        assertEquals(dollars(-70), statement.netIncome)
    }

    @Test
    fun `an expense tag with more refunds than spending is a negative expense`() {
        val electronics = tag("Electronics", TagKind.Expense)
        val groceries = tag("Groceries", TagKind.Expense)
        val statement = compute(entry(500, electronics), entry(-200, groceries))
        assertEquals(
            listOf(groceries.id to dollars(200), electronics.id to dollars(-500)),
            statement.expenseLines.amounts(),
        )
        assertEquals(dollars(300), statement.netIncome)
    }

    @Test
    fun `untagged transactions are split by sign and counted`() {
        val salary = tag("Salary", TagKind.Income)
        val rent = tag("Rent", TagKind.Expense)
        val statement =
            compute(
                entry(5000, salary),
                entry(-2000, rent),
                entry(40, null),
                entry(10, null),
                entry(-25, null),
            )
        assertEquals(
            listOf(salary.id to dollars(5000), null to dollars(50)),
            statement.incomeLines.amounts(),
        )
        assertEquals(
            listOf(rent.id to dollars(2000), null to dollars(25)),
            statement.expenseLines.amounts(),
        )
        assertEquals(dollars(3025), statement.netIncome)
    }

    @Test
    fun `lines are sorted largest first with the untagged line last`() {
        val rent = tag("Rent", TagKind.Expense)
        val groceries = tag("Groceries", TagKind.Expense)
        val fuel = tag("Fuel", TagKind.Expense)
        val statement =
            compute(
                entry(-1000, null),
                entry(-80, fuel),
                entry(-2000, rent),
                entry(-300, groceries),
            )
        assertEquals(
            listOf(rent.id, groceries.id, fuel.id, null),
            statement.expenseLines.map { it.tag?.id },
        )
    }

    @Test
    fun `expense shares are rounded percentages of a positive total`() {
        val (a, b, c) = listOf("A", "B", "C").map { tag(it, TagKind.Expense) }
        assertEquals(
            List(3) { BigDecimal("33.33") },
            compute(entry(-10, a), entry(-10, b), entry(-10, c)).expenseLines.map { it.share },
        )
        assertEquals(
            listOf(BigDecimal("125.00"), BigDecimal("-25.00")),
            compute(entry(-1000, a), entry(200, b)).expenseLines.map { it.share },
            "relative to net expenses",
        )
        assertEquals(listOf(null), compute(entry(200, a)).expenseLines.map { it.share })
    }

    @Test
    fun `a period is ordered and at most two years`() {
        val first = LocalDate.of(2026, 1, 1)
        assertFailsWith<IllegalArgumentException> { Period(first, first.minusDays(1)) }
        assertFailsWith<IllegalArgumentException> {
            Period(first, first.plusDays(Period.MAX_DAYS.toLong()))
        }
        Period(first, first.plusDays(Period.MAX_DAYS - 1L))
    }
}
