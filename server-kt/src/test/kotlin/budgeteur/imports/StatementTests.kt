package budgeteur.imports

import budgeteur.domain.BalanceObservation
import budgeteur.domain.Money
import budgeteur.domain.TransactionDescription
import budgeteur.feature.imports.Formats
import budgeteur.feature.imports.StatementAccount
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StatementTests {
    private val kiwibankHeader = Formats.kiwibank.header

    /** A Kiwibank row with only the fields the format reads filled in. */
    private fun kiwibankRow(date: String, description: String, amount: String, balance: String) =
        "12-3456-0789012-00,$date,$date,$description,EFTPOS PURCHASE,,,,,,,,,$amount,$balance"

    private fun money(cents: Long) = Money(cents)

    @Test
    fun `Kiwibank chequing reads every row`() {
        val statement = parseOk("KiwibankChequing.csv", fixture("KiwibankChequing.csv"))

        assertEquals("Kiwibank", statement.format)
        assertEquals(StatementAccount(number("12-3456-0789012-000")), statement.account)
        assertEquals(192, statement.rows.size)
        val first = statement.rows.first()
        assertEquals(2, first.line, "rows keep their line numbers")
        assertEquals(LocalDate.of(2026, 3, 27), first.date, "the effective date")
        assertEquals("HARBOUR CAFE AUCKLAND", first.description.value)
        assertEquals(money(-850), first.amount, "amounts are as given")
    }

    @Test
    fun `Kiwibank records one observation per processing date`() {
        val statement = parseOk("KiwibankChequing.csv", fixture("KiwibankChequing.csv"))

        assertEquals(79, statement.observations.size, "one per distinct transaction date")
        // Three rows were processed on 28 March; the last one closes the day.
        assertEquals(
            BalanceObservation(LocalDate.of(2026, 3, 28), money(89991)),
            statement.observations.first(),
        )
        assertEquals(
            BalanceObservation(LocalDate.of(2026, 6, 26), money(105399)),
            statement.observations.last(),
            "the statement's closing balance",
        )
    }

    @Test
    fun `Kiwibank savings names chequing as the other party`() {
        val statement = parseOk("KiwibankSavings.csv", fixture("KiwibankSavings.csv"))

        assertEquals(number("12-3456-0789012-001"), statement.account.number)
        assertEquals(
            20,
            statement.rows.count { it.otherPartyAccount == number("12-3456-0789012-000") },
            "the transfers to chequing",
        )
        assertTrue(statement.rows.any { it.otherPartyAccount == null })
    }

    @Test
    fun `ASB card reads the preamble and negates amounts`() {
        val statement = parseOk("AsbCard.csv", fixture("AsbCard.csv"))

        assertEquals("ASB card", statement.format)
        assertEquals(
            StatementAccount(number("XXXX-XXXX-XXXX-0000"), "Visa Light"),
            statement.account,
        )
        assertEquals(8, statement.rows.size)
        val first = statement.rows.first()
        assertEquals(LocalDate.of(2026, 6, 16), first.date, "the transaction date")
        assertEquals(money(-70700), first.amount, "a purchase is money out")
        assertEquals("CITY COMPUTERS AUCKLAND", first.description.value, "quotes are removed")
        val payment = statement.rows.first { it.description.value == "PAYMENT RECEIVED THANK YOU" }
        assertEquals(money(72700), payment.amount, "a payment is money in")
        assertTrue(statement.observations.isEmpty(), "ASB cards have no balance")
    }

    @Test
    fun `a file with no known header lists the headers to compare`() {
        val error = parseErrors("export.csv", "Date,Payee,Amount\n2026-03-01,Cafe,-4.50\n").single()

        assertEquals("export.csv", error.fileName)
        assertNull(error.line, "the whole file is rejected")
        assertContains(error.message, "Date,Payee,Amount")
        assertContains(error.message, kiwibankHeader)
        assertContains(error.message, Formats.asbCard.header)
    }

    @Test
    fun `a header with a changed column is not detected`() {
        val header = kiwibankHeader.replace(",Balance", ",Running Balance")
        parseErrors("changed.csv", header + "\n" + kiwibankRow("2026-03-01", "Cafe", "-4.50", "10"))
    }

    @Test
    fun `a format without a preamble needs its header first`() {
        val text =
            "Exported 2026-03-01\n$kiwibankHeader\n" +
                kiwibankRow("2026-03-01", "Cafe", "-4.50", "10.00")
        assertContains(parseErrors("kiwibank.csv", text).first().message, "not on the first line")
    }

    @Test
    fun `an ASB card file without its card line is rejected`() {
        val text =
            "Created date / time : 27 June 2026 / 10:25:49\n${Formats.asbCard.header}\n" +
                "2026/06/17,2026/06/16,2026061701,DEBIT,0000,\"Cafe\",4.50\n"
        assertContains(parseErrors("card.csv", text).first().message, "no card number")
    }

    @Test
    fun `every failing row is reported with its line`() {
        val text =
            listOf(
                    kiwibankHeader,
                    kiwibankRow("2026-03-01", "Cafe", "-4.50", "10.00"),
                    kiwibankRow("01/03/2026", "Cafe", "-4.50", "5.50"),
                    "",
                    kiwibankRow("2026-03-02", "Cafe", "four", "5.50"),
                )
                .joinToString("\n")

        val errors = parseErrors("bad.csv", text)

        assertEquals(listOf(3, 3, 5), errors.map { it.line }, "both bad dates, then the amount")
        assertContains(errors.last().describe(), "bad.csv line 5: Amount \"four\" is not an amount")
    }

    @Test
    fun `a row with the wrong number of fields is reported`() {
        val errors = parseErrors("short.csv", "$kiwibankHeader\n12-3456-0789012-00,2026-03-01")
        assertContains(errors.first().message, "expected 15 fields")
    }

    @Test
    fun `balance dates out of the declared order are rejected`() {
        val text =
            listOf(
                    kiwibankHeader,
                    kiwibankRow("2026-03-02", "Cafe", "-4.50", "10.00"),
                    kiwibankRow("2026-03-01", "Cafe", "-4.50", "5.50"),
                )
                .joinToString("\n")

        val error = parseErrors("newest-first.csv", text).first()

        assertEquals(3, error.line, "the first row out of order")
        assertContains(error.message, "oldest first")
    }

    @Test
    fun `every row must name the same account`() {
        val text =
            listOf(
                    kiwibankHeader,
                    kiwibankRow("2026-03-01", "Cafe", "-4.50", "10.00"),
                    kiwibankRow("2026-03-01", "Cafe", "-4.50", "5.50").replace("-00,", "-01,"),
                )
                .joinToString("\n")

        assertEquals(3, parseErrors("two-accounts.csv", text).first().line)
    }

    @Test
    fun `descriptions handle quotes, length, and other scripts`() {
        val long = "x".repeat(300)
        val text =
            listOf(
                    kiwibankHeader,
                    kiwibankRow("2026-03-01", "\"Cafe, \"\"The Bean\"\"\"", "-4.50", "10.00"),
                    kiwibankRow("2026-03-01", long, "-1.00", "9.00"),
                    kiwibankRow("2026-03-01", "Kai Māori café", "-1.00", "8.00"),
                    // An empty description falls back to the transaction type.
                    kiwibankRow("2026-03-01", "", "-1.00", "7.00"),
                )
                .joinToString("\r\n")

        assertEquals(
            listOf(
                "Cafe, \"The Bean\"",
                "x".repeat(TransactionDescription.MAX_LENGTH),
                "Kai Māori café",
                "EFTPOS PURCHASE",
            ),
            parseOk("edge.csv", text).rows.map { it.description.value },
        )
    }
}
