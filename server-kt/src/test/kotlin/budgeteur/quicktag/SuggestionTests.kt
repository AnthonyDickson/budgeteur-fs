package budgeteur.quicktag

import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import budgeteur.domain.Tag
import budgeteur.domain.TagColor
import budgeteur.domain.TagKind
import budgeteur.domain.TagName
import budgeteur.domain.TransactionDescription
import budgeteur.feature.quicktag.QueueBatch
import budgeteur.feature.quicktag.readQueue
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

class SuggestionTests {
    private fun tag(name: String, kind: TagKind) =
        Tag(UUID.randomUUID(), TagName.unsafe(name), TagColor.Green, kind)

    private val salary = tag("Salary", TagKind.Income)
    private val groceries = tag("Groceries", TagKind.Expense)
    private val dining = tag("Dining", TagKind.Expense)

    private fun rule(pattern: String, target: RuleTarget) =
        Rule(UUID.randomUUID(), RulePattern.unsafe(pattern), target)

    private val rules =
        listOf(
            rule("TO SAVINGS", RuleTarget.Transfer),
            rule("ASB CARD", RuleTarget.Transfer),
            rule("COUNTDOWN", RuleTarget.Tag(groceries.id)),
            rule("CAFE", RuleTarget.Tag(dining.id)),
            rule("PAYROLL", RuleTarget.Tag(salary.id)),
        )

    /** Newest first, as the queue is read. */
    private val queue =
        listOf(
            "PAYROLL ACME",
            "TRANSFER TO SAVINGS",
            "Countdown Ponsonby",
            "ASB CARD 1234",
            "Rent",
            "Cafe Hanoi",
            "COUNTDOWN METRO",
        )

    private fun read(filter: RuleTarget?, batchSize: Int): QueueBatch<String> =
        readQueue(
            batchSize,
            rules,
            listOf(salary, groceries, dining),
            TransactionDescription::unsafe,
            filter,
            queue,
        )

    private fun QueueBatch<String>.patterns() = batch.map {
        it.transaction to it.suggestion?.pattern?.value
    }

    @Test
    fun `each row is suggested the winning rule's target`() {
        val read = read(null, 50)

        assertEquals(
            listOf(
                "PAYROLL ACME" to "PAYROLL",
                "TRANSFER TO SAVINGS" to "TO SAVINGS",
                "Countdown Ponsonby" to "COUNTDOWN",
                "ASB CARD 1234" to "ASB CARD",
                "Rent" to null,
                "Cafe Hanoi" to "CAFE",
                "COUNTDOWN METRO" to "COUNTDOWN",
            ),
            read.patterns(),
        )
        assertEquals(
            listOf(
                RuleTarget.Tag(salary.id),
                RuleTarget.Transfer,
                RuleTarget.Tag(groceries.id),
                RuleTarget.Transfer,
                RuleTarget.Tag(dining.id),
                RuleTarget.Tag(groceries.id),
            ),
            read.batch.mapNotNull { it.suggestion?.target },
        )
    }

    @Test
    fun `counts cover the whole queue, in button order`() {
        assertEquals(
            listOf(
                RuleTarget.Tag(dining.id) to 1,
                RuleTarget.Tag(groceries.id) to 2,
                RuleTarget.Tag(salary.id) to 1,
                RuleTarget.Transfer to 2,
            ),
            read(null, 2).counts,
            "expense tags then income tags by name, then transfers from both rules together",
        )
    }

    @Test
    fun `the filter keeps the rows suggested its target`() {
        val read = read(RuleTarget.Transfer, 1)

        assertEquals(listOf("TRANSFER TO SAVINGS" to "TO SAVINGS"), read.patterns())
        assertEquals(2, read.total, "the total counts the filtered rows")
        assertEquals(4, read.counts.size, "the counts still cover the whole queue")
    }

    @Test
    fun `without a filter the total is the whole queue`() {
        val read = read(null, 2)
        assertEquals(2, read.batch.size)
        assertEquals(7, read.total)
    }
}
