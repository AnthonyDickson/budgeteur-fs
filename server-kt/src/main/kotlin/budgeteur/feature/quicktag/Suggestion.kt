package budgeteur.feature.quicktag

import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import budgeteur.domain.Tag
import budgeteur.domain.TagKind
import budgeteur.domain.TransactionDescription
import budgeteur.domain.winner

/**
 * The proposal for a queued transaction: the winning rule's target, and the rule's pattern so the
 * user can check why. Computed when the queue is read, never stored. See decision 6 in
 * docs/transfer-rules.md.
 */
data class Suggestion(val target: RuleTarget, val pattern: RulePattern)

/** A queued transaction and its suggestion, if any. */
data class Suggested<T>(val transaction: T, val suggestion: Suggestion?)

/** A batch of the queue, as the queue read returns it. */
data class QueueBatch<T>(
    /**
     * The first batch of the queue, or of the queued transactions suggested the filter's target.
     */
    val batch: List<Suggested<T>>,
    /** How many transactions the queue holds, or how many are suggested the filter's target. */
    val total: Int,
    /**
     * How many queued transactions are suggested each target, over the whole queue, in the order of
     * the row buttons.
     */
    val counts: List<Pair<RuleTarget, Int>>,
)

/**
 * The suggestion for each description: the winning rule's target and pattern, whatever the target.
 * Apply it to the rules once and reuse the result for many descriptions.
 */
fun suggester(rules: List<Rule>): (TransactionDescription) -> Suggestion? {
    val winner = winner(rules)
    return { description -> winner(description)?.let { Suggestion(it.target, it.pattern) } }
}

/**
 * Where a target's count sits, as the row buttons are ordered: expense tags, then income tags, each
 * by name, then transfer. See decision 5 in docs/quick-tagging.md.
 */
private fun buttonOrder(tags: List<Tag>): Comparator<RuleTarget> {
    val byId = tags.associateBy { it.id }
    fun rank(target: RuleTarget): Pair<Int, String> =
        when (target) {
            is RuleTarget.Tag -> {
                val tag = byId[target.tagId]
                when {
                    // A rule's tag is the user's, so in practice every tag is found.
                    tag == null -> 2 to target.tagId.toString()
                    tag.kind == TagKind.Expense -> 0 to tag.name.value
                    else -> 1 to tag.name.value
                }
            }
            RuleTarget.Transfer -> 3 to ""
        }
    return compareBy<RuleTarget> { rank(it).first }.thenBy { rank(it).second }
}

/**
 * Reads a batch of the queue: suggests every queued transaction, counts the suggestions over the
 * whole queue, and keeps the transactions suggested the filter's target, if any. [queue] is newest
 * first. Suggestions are computed in memory, so the filter and its total are too. See decision 7 in
 * docs/transfer-rules.md.
 */
fun <T> readQueue(
    batchSize: Int,
    rules: List<Rule>,
    tags: List<Tag>,
    describe: (T) -> TransactionDescription,
    filter: RuleTarget?,
    queue: List<T>,
): QueueBatch<T> {
    val suggest = suggester(rules)
    val suggested = queue.map { Suggested(it, suggest(describe(it))) }
    val counts =
        suggested
            .mapNotNull { it.suggestion?.target }
            .groupingBy { it }
            .eachCount()
            .toList()
            .sortedWith(compareBy(buttonOrder(tags)) { it.first })
    val kept =
        if (filter == null) suggested else suggested.filter { it.suggestion?.target == filter }
    return QueueBatch(kept.take(batchSize), kept.size, counts)
}
