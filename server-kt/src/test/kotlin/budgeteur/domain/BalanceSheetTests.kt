package budgeteur.domain

import arrow.core.raise.context.either
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BalanceSheetTests {
    private val asOf = LocalDate.parse("2026-03-01")

    private fun item(side: Side, term: Term, amount: Long) =
        ItemValue(
            BalanceSheetItem(UUID.randomUUID(), ItemName.unsafe("Item"), side, term),
            ItemObservation(asOf, Magnitude.unsafe(dollars(amount))),
        )

    private fun account(term: Term, balance: Long?) =
        AccountBalance(
            Account(UUID.randomUUID(), null, AccountName.unsafe("Account"), term),
            balance?.let { BalanceObservation(asOf, dollars(it)) },
        )

    private fun dollars(amount: Long) = Money(amount * 100)

    /** One item per side and term, so a total that sums the wrong lines differs. */
    private val oneOfEach =
        BalanceSheet(
            listOf(
                item(Side.Asset, Term.Current, 2_000),
                item(Side.Asset, Term.NonCurrent, 400_000),
                item(Side.Liability, Term.Current, 1_500),
                item(Side.Liability, Term.NonCurrent, 300_000),
            ),
            emptyList(),
        )

    @Test
    fun `each total sums its side and term`() {
        with(oneOfEach) {
            assertEquals(dollars(2_000), totalCurrentAssets)
            assertEquals(dollars(400_000), totalNonCurrentAssets)
            assertEquals(dollars(1_500), totalCurrentLiabilities)
            assertEquals(dollars(300_000), totalNonCurrentLiabilities)
            assertEquals(dollars(402_000), totalAssets)
            assertEquals(dollars(301_500), totalLiabilities)
            assertEquals(dollars(100_500), netWorth)
            assertEquals(dollars(500), workingCapital)
        }
    }

    @Test
    fun `an empty sheet totals zero`() {
        val empty = BalanceSheet(emptyList(), emptyList())
        assertEquals(Money.ZERO, empty.netWorth)
        assertEquals(Money.ZERO, empty.workingCapital)
    }

    @Test
    fun `an account's side follows the sign of its balance`() {
        assertEquals(Side.Asset to dollars(10), BalanceSheet.accountSide(dollars(10)))
        assertEquals(Side.Asset to Money.ZERO, BalanceSheet.accountSide(Money.ZERO))
        assertEquals(Side.Liability to dollars(10), BalanceSheet.accountSide(dollars(-10)))
    }

    @Test
    fun `accounts count towards the totals, and unknown balances are listed apart`() {
        val unknown = account(Term.Current, null)
        val sheet =
            oneOfEach.copy(
                accounts =
                    listOf(
                        account(Term.Current, 1_000),
                        account(Term.Current, -400),
                        account(Term.NonCurrent, -50_000),
                        unknown,
                    )
            )

        assertEquals(dollars(3_000), sheet.totalCurrentAssets)
        assertEquals(dollars(1_900), sheet.totalCurrentLiabilities)
        assertEquals(dollars(350_000), sheet.totalNonCurrentLiabilities)
        assertEquals(dollars(51_100), sheet.netWorth)
        assertEquals(listOf(unknown.account), sheet.unknownBalances)
    }

    @Test
    fun `an item's value cannot be negative`() {
        assertTrue(either { Magnitude.create(Money(-1)) }.isLeft())
        assertEquals(Money.ZERO, either { Magnitude.create(Money.ZERO) }.getOrNull()?.amount)
    }

    @Test
    fun `item names are trimmed and bounded`() {
        assertEquals("House", either { ItemName.create("  House ") }.getOrNull()?.value)
        assertTrue(either { ItemName.create(" ") }.isLeft())
        val longest = "x".repeat(ItemName.MAX_LENGTH)
        assertEquals(longest, either { ItemName.create(longest) }.getOrNull()?.value)
        assertTrue(either { ItemName.create(longest + "x") }.isLeft())
    }

    @Test
    fun `sides parse by name`() {
        Side.entries.forEach { assertEquals(it, either { Side.parse(it.name) }.getOrNull()) }
        assertTrue(either { Side.parse("asset") }.isLeft())
    }
}
