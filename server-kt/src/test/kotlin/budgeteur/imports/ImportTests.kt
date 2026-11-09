package budgeteur.imports

import budgeteur.domain.AccountNumber
import budgeteur.domain.Categorisation
import budgeteur.domain.Money
import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import budgeteur.domain.Source
import budgeteur.domain.TransactionDescription
import budgeteur.feature.imports.ImportCounts
import budgeteur.feature.imports.Statement
import budgeteur.feature.imports.StatementAccount
import budgeteur.feature.imports.StatementRow
import budgeteur.feature.imports.dropDuplicates
import budgeteur.feature.imports.missingAccounts
import budgeteur.feature.imports.plan
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ImportTests {
    private val chequing = number("12-3456-0789012-000")
    private val savings = number("12-3456-0789012-001")

    private fun row(hash: String, description: String, otherParty: AccountNumber? = null) =
        StatementRow(
            line = 2,
            date = LocalDate.of(2026, 3, 1),
            description = TransactionDescription.unsafe(description),
            amount = Money(-1000),
            balance = null,
            otherPartyAccount = otherParty,
            importHash = hash,
        )

    private fun statement(account: AccountNumber, vararg rows: StatementRow) =
        Statement("statement.csv", "Kiwibank", StatementAccount(account), rows.toList(), listOf())

    private fun rule(pattern: String, target: RuleTarget) =
        Rule(UUID.randomUUID(), RulePattern.unsafe(pattern), target)

    @Test
    fun `duplicates are dropped against the user and the request`() {
        val statements =
            listOf(
                statement(chequing, row("a", "CAFE"), row("b", "CAFE")),
                // An overlapping export of the same account.
                statement(chequing, row("b", "CAFE"), row("c", "CAFE")),
            )

        val (kept, skipped) = dropDuplicates(setOf("a"), statements)

        assertEquals(listOf("b", "c"), kept.map { (_, row) -> row.importHash })
        assertEquals(2, skipped)
    }

    @Test
    fun `accounts are created once for numbers the user lacks`() {
        val statements = listOf(statement(chequing), statement(savings), statement(savings))
        assertEquals(
            listOf(savings),
            missingAccounts(setOf(chequing), statements).map { it.number },
        )
    }

    @Test
    fun `a transfer is marked and untagged, other rows get tags`() {
        val tagId = UUID.randomUUID()
        val accountIds = mapOf(chequing to UUID.randomUUID(), savings to UUID.randomUUID())

        val (transactions, counts) =
            plan(
                UUID::randomUUID,
                accountIds,
                emptySet(),
                listOf(rule("TRANSFER", RuleTarget.Tag(tagId))),
                listOf(
                    statement(
                        chequing,
                        row("a", "TRANSFER TO SAVINGS", savings),
                        row("b", "TRANSFER TO JANE", number("06-6543-0987654-00")),
                        row("c", "CAFE"),
                    )
                ),
            )

        assertEquals(
            listOf(
                Categorisation.Transfer(Source.Detected),
                Categorisation.Tagged(tagId, Source.Rule),
                null,
            ),
            transactions.map { it.categorisation },
            "only the transfer to the user's own account is marked",
        )
        assertEquals(ImportCounts(3, 0, 1, 1), counts)
        assertTrue(transactions.all { it.transaction.accountId == accountIds[chequing] })
    }

    @Test
    fun `a row a transfer rule wins stays untagged and uncounted`() {
        val rules =
            listOf(
                rule("TRANSFER", RuleTarget.Tag(UUID.randomUUID())),
                rule("TRANSFER TO SAVINGS", RuleTarget.Transfer),
            )

        val (transactions, counts) =
            plan(
                UUID::randomUUID,
                mapOf(chequing to UUID.randomUUID()),
                emptySet(),
                rules,
                listOf(statement(chequing, row("a", "TRANSFER TO SAVINGS"))),
            )

        assertEquals(listOf(null), transactions.map { it.categorisation })
        assertEquals(0 to 0, counts.transfers to counts.taggedByRules)
    }
}
