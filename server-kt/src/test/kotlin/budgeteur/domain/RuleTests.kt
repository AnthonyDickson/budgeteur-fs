package budgeteur.domain

import arrow.core.raise.context.either
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RuleTests {
    private fun pattern(raw: String) = either { RulePattern.create(raw) }.getOrNull()!!

    @Test
    fun `patterns are the same ignoring case, including outside ASCII`() {
        assertTrue(pattern("CAFÉ").isSameAs(pattern("café")))
        assertTrue(!pattern("CAFE").isSameAs(pattern("CAFÉ")))
    }

    @Test
    fun `a target's kind and tag id must agree`() {
        val tagId = UUID.randomUUID()
        assertEquals(RuleTarget.Tag(tagId), either { RuleTarget.create("Tag", tagId) }.getOrNull())
        assertEquals(
            RuleTarget.Transfer,
            either { RuleTarget.create("Transfer", null) }.getOrNull(),
        )
        assertTrue(either { RuleTarget.create("Tag", null) }.isLeft())
        assertTrue(either { RuleTarget.create("Transfer", tagId) }.isLeft())
        assertTrue(either { RuleTarget.create("tag", tagId) }.isLeft())
    }
}

class RuleWinnerTests {
    private fun rule(pattern: String, target: RuleTarget = RuleTarget.Tag(UUID.randomUUID())) =
        Rule(UUID.randomUUID(), RulePattern.unsafe(pattern), target)

    private fun winningPattern(rules: List<Rule>, description: String) =
        winner(rules)(TransactionDescription.unsafe(description))?.pattern?.value

    @Test
    fun `no rule wins when none matches`() {
        assertEquals(null, winningPattern(listOf(rule("COUNTDOWN")), "New World"))
    }

    @Test
    fun `the longest matching pattern wins`() {
        val rules = listOf(rule("COUNTDOWN"), rule("COUNTDOWN FUEL"), rule("FUEL"))
        assertEquals("COUNTDOWN FUEL", winningPattern(rules, "Countdown Fuel Ponsonby"))
        assertEquals("COUNTDOWN", winningPattern(rules, "Countdown Ponsonby"))
    }

    @Test
    fun `equal lengths are ordered by the comparison, whatever the input order`() {
        val rules = listOf(rule("bar"), rule("FOO"), rule("Baz"))
        listOf(rules, rules.reversed(), rules.drop(1) + rules.take(1)).forEach {
            assertEquals("bar", winningPattern(it, "foo bar baz"))
        }
    }

    @Test
    fun `the target does not change which rule wins`() {
        assertEquals(
            "TRANSFER TO RENT",
            winningPattern(
                listOf(rule("TRANSFER TO", RuleTarget.Transfer), rule("TRANSFER TO RENT")),
                "TRANSFER TO RENT ACCOUNT",
            ),
        )
        assertEquals(
            "TRANSFER TO SAVINGS",
            winningPattern(
                listOf(rule("TRANSFER"), rule("TRANSFER TO SAVINGS", RuleTarget.Transfer)),
                "TRANSFER TO SAVINGS",
            ),
        )
    }
}
