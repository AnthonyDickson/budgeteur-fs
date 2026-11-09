package budgeteur.autotag

import budgeteur.domain.Categorisation
import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import budgeteur.domain.Source
import budgeteur.domain.TransactionDescription
import budgeteur.feature.autotag.AutoTagAction
import budgeteur.feature.autotag.Candidate
import budgeteur.feature.autotag.Change
import budgeteur.feature.autotag.Counts
import budgeteur.feature.autotag.changes
import budgeteur.feature.autotag.counts
import budgeteur.feature.autotag.matches
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

class AutoTagTests {
    private val groceries = UUID.randomUUID()
    private val fuel = UUID.randomUUID()
    private val dining = UUID.randomUUID()

    private fun rule(pattern: String, target: RuleTarget) =
        Rule(UUID.randomUUID(), RulePattern.unsafe(pattern), target)

    private fun rule(pattern: String, tagId: UUID) = rule(pattern, RuleTarget.Tag(tagId))

    private fun description(raw: String) = TransactionDescription.unsafe(raw)

    private fun candidate(raw: String, categorisation: Categorisation? = null) =
        Candidate(UUID.randomUUID(), description(raw), categorisation)

    private fun ruleTag(tagId: UUID) = Categorisation.Tagged(tagId, Source.Rule)

    private val rules = listOf(rule("COUNTDOWN", groceries), rule("COUNTDOWN FUEL", fuel))

    private val untaggedMatch = candidate("PAY Countdown Ponsonby")
    private val untaggedNoMatch = candidate("Rent")
    // The fuel rule now wins over the groceries tag a rule set earlier.
    private val staleRuleTag = candidate("Countdown Fuel", ruleTag(groceries))
    private val orphanRuleTag = candidate("Pak'nSave", ruleTag(groceries))
    private val currentRuleTag = candidate("Countdown", ruleTag(groceries))
    private val manualTag =
        candidate("Countdown Fuel", Categorisation.Tagged(dining, Source.Manual))
    private val all =
        listOf(
            untaggedMatch,
            untaggedNoMatch,
            staleRuleTag,
            orphanRuleTag,
            currentRuleTag,
            manualTag,
        )

    @Test
    fun `TagUntagged only tags untagged transactions`() {
        assertEquals(
            listOf(Change.Tagged(untaggedMatch.transactionId, ruleTag(groceries))),
            changes(AutoTagAction.TagUntagged, rules, all),
        )
    }

    @Test
    fun `Retag tags, changes, and clears rule tags, and counts each`() {
        val changes = changes(AutoTagAction.Retag, rules, all)
        assertEquals(
            listOf(
                Change.Tagged(untaggedMatch.transactionId, ruleTag(groceries)),
                Change.Changed(staleRuleTag.transactionId, ruleTag(fuel)),
                Change.Cleared(orphanRuleTag.transactionId),
            ),
            changes,
            "unchanged rule tags and manual tags do not change",
        )
        assertEquals(Counts(tagged = 1, changed = 1, cleared = 1), changes.counts())
    }

    @Test
    fun `a transfer rule winner gets no tag, and its rule tag clears`() {
        val rules =
            listOf(rule("COUNTDOWN FUEL", fuel), rule("COUNTDOWN FUEL TOP UP", RuleTarget.Transfer))
        val untagged = candidate("Countdown Fuel Top Up")
        val ruleTagged = candidate("Countdown Fuel Top Up", ruleTag(fuel))

        assertEquals(
            emptyList(),
            changes(AutoTagAction.TagUntagged, rules, listOf(untagged, ruleTagged)),
        )
        assertEquals(
            listOf(Change.Cleared(ruleTagged.transactionId)),
            changes(AutoTagAction.Retag, rules, listOf(untagged, ruleTagged)),
            "re-tag clears the rule tag rather than fall through to a shorter pattern",
        )
    }

    @Test
    fun `matches counts every match and samples distinct descriptions`() {
        val descriptions =
            listOf("Countdown A", "Rent", "Countdown A", "countdown B", "C", "D", "E", "F")
                .map(::description) + (1..6).map { description("COUNTDOWN $it") }

        val matches = matches(RulePattern.unsafe("COUNTDOWN"), descriptions)

        assertEquals(9, matches.count)
        assertEquals(descriptions.size, matches.total)
        assertEquals(
            listOf("Countdown A", "countdown B", "COUNTDOWN 1", "COUNTDOWN 2", "COUNTDOWN 3"),
            matches.samples.map { it.value },
        )
        assertEquals(emptyList(), matches(RulePattern.unsafe("NOPE"), descriptions).samples)
    }
}
