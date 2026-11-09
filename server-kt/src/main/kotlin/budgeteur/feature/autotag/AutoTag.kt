package budgeteur.feature.autotag

import arrow.core.raise.Raise
import arrow.core.raise.context.ensureNotNull
import budgeteur.domain.Categorisation
import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.TransactionDescription
import budgeteur.domain.matches
import budgeteur.domain.winner
import java.util.UUID

// The slice's pure logic: which categorisations a run changes, and what a pattern matches.

/** Which transactions an auto-tagging run recomputes. See decision 5 in docs/auto-tagging.md. */
enum class AutoTagAction {
    /** Apply rules to untagged transactions only. */
    TagUntagged,

    /** Recompute every transaction without a manual tag. */
    Retag;

    /** The categorisation transition the action applies. */
    val transition: (Categorisation?, Categorisation?) -> Categorisation?
        get() =
            when (this) {
                TagUntagged -> Categorisation::tagUntagged
                Retag -> Categorisation::retag
            }

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): AutoTagAction =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for AutoTagAction, expecting one of " +
                    "\"TagUntagged\" or \"Retag\"."
            }
    }
}

/** A transaction a run may tag: its description and current categorisation. */
data class Candidate(
    val transactionId: UUID,
    val description: TransactionDescription,
    val categorisation: Categorisation?,
)

/** A change to one transaction's categorisation. A transaction a run leaves alone has none. */
sealed interface Change {
    val transactionId: UUID

    /** An untagged transaction got a rule tag. */
    data class Tagged(override val transactionId: UUID, val categorisation: Categorisation) : Change

    /** A rule tag changed to another rule's tag. */
    data class Changed(override val transactionId: UUID, val categorisation: Categorisation) :
        Change

    /** A rule tag no rule wins any more was removed. */
    data class Cleared(override val transactionId: UUID) : Change
}

/** How many transactions a run tagged, changed, and cleared. */
data class Counts(val tagged: Int, val changed: Int, val cleared: Int)

/** What a pattern matches among a user's transactions. See decision 7 in docs/auto-tagging.md. */
data class Matches(
    val count: Int,
    val total: Int,
    /**
     * Distinct descriptions from the most recent matches, most recent first, so a recurring
     * merchant does not fill the samples with copies.
     */
    val samples: List<TransactionDescription>,
)

const val MAX_SAMPLES = 5

/**
 * The categorisation changes a run makes: each candidate goes through the action's transition with
 * the winning rule's proposal as the policy applies it, so a transfer rule's winner gets no rule
 * tag. Only the candidates whose categorisation differs are returned. See decision 3 in
 * docs/transfer-rules.md.
 */
fun changes(action: AutoTagAction, rules: List<Rule>, candidates: List<Candidate>): List<Change> {
    val winner = winner(rules)
    return candidates.mapNotNull { candidate ->
        val applied = winner(candidate.description)?.let { Categorisation.applyRule(it.target) }
        val before = candidate.categorisation
        val after = action.transition(applied, before)
        when {
            before == after -> null
            after == null -> Change.Cleared(candidate.transactionId)
            before == null -> Change.Tagged(candidate.transactionId, after)
            else -> Change.Changed(candidate.transactionId, after)
        }
    }
}

fun List<Change>.counts() =
    Counts(
        tagged = count { it is Change.Tagged },
        changed = count { it is Change.Changed },
        cleared = count { it is Change.Cleared },
    )

/**
 * What [pattern] matches among the [descriptions], which are ordered most recent first. Counts
 * matches, not wins: whether the rule would win depends on the other rules.
 */
fun matches(pattern: RulePattern, descriptions: List<TransactionDescription>): Matches {
    val matching = descriptions.filter { pattern.matches(it) }
    return Matches(matching.size, descriptions.size, matching.distinct().take(MAX_SAMPLES))
}
