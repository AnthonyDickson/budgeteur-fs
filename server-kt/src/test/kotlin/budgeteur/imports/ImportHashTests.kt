package budgeteur.imports

import budgeteur.feature.imports.Formats
import budgeteur.feature.imports.ImportHash
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class ImportHashTests {
    private fun hashes(fileName: String, text: String): List<String> =
        parseOk(fileName, text).rows.map { it.importHash }

    private fun firstHash(fileName: String, text: String) = hashes(fileName, text).first()

    private fun row(description: String, amount: String, balance: String) =
        "12-3456-0789012-00,2026-03-01,2026-03-02,$description,EFTPOS PURCHASE,,,,,,,,,$amount," +
            balance

    // Pinned to the F# server's values, which were computed independently with sha256sum. If a
    // refactor changes them, every stored hash stops matching and re-imports duplicate every
    // transaction.

    @Test
    fun `the hash input is the version, number, and fields`() {
        assertEquals(
            "fe43126b21eca011af6edc60abaeb2420d44d969ce1086a27374e3b7f6e2e3bd",
            ImportHash.compute(number("12-3456-0789012-00"), listOf("abc")),
        )
    }

    @Test
    fun `Kiwibank hashes the processing date, amount, and balance`() {
        assertEquals(
            "7e47e795e223ab5f00637c79d242f979b125920ce61709f51019028a310a6ae6",
            firstHash("KiwibankChequing.csv", fixture("KiwibankChequing.csv")),
        )
    }

    @Test
    fun `ASB card hashes the unique id`() {
        assertEquals(
            "851b143621337576ae3c43edfa3949acf430c06987388881e71e5a04d4d99117",
            firstHash("AsbCard.csv", fixture("AsbCard.csv")),
        )
    }

    @Test
    fun `every row in the fixtures has its own hash`() {
        listOf("KiwibankChequing.csv", "KiwibankSavings.csv", "AsbCard.csv").forEach { name ->
            val hashes = hashes(name, fixture(name))
            assertEquals(hashes.distinct(), hashes, "no two rows of $name share a hash")
        }
    }

    @Test
    fun `a changed description or format keeps the hash`() {
        // Descriptions and quoting are not identity fields, so a reworded export still matches.
        assertEquals(
            firstHash("a.csv", kiwibankText(row("CAFE", "-4.50", "10.00"))),
            firstHash("b.csv", kiwibankText(row("\"Cafe, Auckland\"", "-4.5", "10"))),
        )
    }

    @Test
    fun `identical purchases on a day differ by balance`() {
        val hashes =
            hashes(
                "twice.csv",
                kiwibankText(row("CAFE", "-4.50", "10.00"), row("CAFE", "-4.50", "5.50")),
            )
        assertEquals(2, hashes.distinct().size, "the running balance tells them apart")
    }

    @Test
    fun `the same row in another account differs`() {
        val chequing = row("CAFE", "-4.50", "10.00")
        val savings = chequing.replace("-00,", "-01,")
        assertNotEquals(
            firstHash("a.csv", kiwibankText(chequing)),
            firstHash("b.csv", kiwibankText(savings)),
        )
    }

    private fun kiwibankText(vararg rows: String) =
        (listOf(Formats.kiwibank.header) + rows).joinToString("\n")
}
