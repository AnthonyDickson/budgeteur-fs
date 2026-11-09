package budgeteur.domain

import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BalanceSheetHistoryTests {
    private fun day(d: Int) = LocalDate.of(2026, 3, d)

    private fun item(name: String, closedOn: LocalDate? = null) =
        BalanceSheetItem(
            UUID.randomUUID(),
            ItemName.unsafe(name),
            Side.Asset,
            Term.NonCurrent,
            closedOn,
        )

    private fun value(d: Int, dollars: Long) =
        ItemObservation(day(d), Magnitude.unsafe(Money(dollars * 100)))

    private fun account(name: String, closedOn: LocalDate? = null) =
        Account(UUID.randomUUID(), null, AccountName.unsafe(name), Term.Current, closedOn)

    private fun balance(d: Int, dollars: Long) = BalanceObservation(day(d), Money(dollars * 100))

    @Test
    fun `each line takes its latest observation on or before the date`() {
        val house = item("House")
        val sheet =
            BalanceSheetHistory(
                    listOf(house to listOf(value(12, 500), value(1, 300), value(9, 400))),
                    emptyList(),
                )
                .asOf(day(10))
        assertEquals(listOf(day(9)), sheet.items.map { it.current.asOf }, "not the 12th")
        assertEquals(Money(40000), sheet.netWorth)
    }

    @Test
    fun `a line enters the sheet at its first observation`() {
        val sheet =
            BalanceSheetHistory(
                    listOf(item("Car") to listOf(value(5, 9000))),
                    listOf(account("Credit card") to listOf(balance(6, -400))),
                )
                .asOf(day(4))
        assertTrue(sheet.items.isEmpty(), "the car has no value yet")
        assertTrue(sheet.accounts.isEmpty(), "the card is left out, not listed as unknown")
        assertTrue(!sheet.hasKnownLines)
    }

    @Test
    fun `an account without observations is unknown`() {
        val card = account("Credit card")
        val sheet = BalanceSheetHistory(emptyList(), listOf(card to emptyList())).asOf(day(4))
        assertEquals(listOf(card), sheet.unknownBalances)
    }

    @Test
    fun `a line leaves the sheet on its close date`() {
        val history =
            BalanceSheetHistory(
                listOf(item("House", day(5)) to listOf(value(1, 300))),
                listOf(account("Old card", day(5)) to listOf(balance(1, -50))),
            )
        assertEquals(Money(25000), history.asOf(day(4)).netWorth, "both count the day before")
        val onTheDay = history.asOf(day(5))
        assertTrue(onTheDay.items.isEmpty() && onTheDay.accounts.isEmpty())
    }

    @Test
    fun `the first observation is the earliest of any line`() {
        val history =
            BalanceSheetHistory(
                listOf(item("House") to listOf(value(9, 1))),
                listOf(account("Card") to listOf(balance(3, 1), balance(7, 1))),
            )
        assertEquals(day(3), history.firstObservation)
        assertEquals(null, BalanceSheetHistory(emptyList(), emptyList()).firstObservation)
    }
}
