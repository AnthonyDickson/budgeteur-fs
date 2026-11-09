package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import arrow.core.raise.context.raise
import java.util.UUID

/**
 * Text a description contains, under the rule comparison: trimmed, non-blank, and at most
 * [MAX_LENGTH] characters. Transaction search validates its text the same way.
 */
@JvmInline
value class RulePattern private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 128

        context(_: Raise<String>)
        fun create(raw: String): RulePattern {
            val pattern = raw.trim()
            ensure(pattern.isNotEmpty()) { "Rule pattern cannot be null or whitespace" }
            ensure(pattern.length <= MAX_LENGTH) {
                "Rule pattern is too long. Patterns must be at most $MAX_LENGTH characters, " +
                    "but got ${pattern.length}"
            }
            return RulePattern(pattern)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = RulePattern(value)

        /**
         * Where [pattern] first occurs in [description] under the rule comparison, or -1. The
         * comparison folds case one character at a time, independent of locale, as the F# server's
         * ordinal ignore-case comparison does. A locale-sensitive one would depend on the server's
         * settings.
         */
        fun indexIn(description: String, pattern: String): Int =
            description.indexOf(pattern, ignoreCase = true)
    }
}

/**
 * Whether two patterns are the same under the rule comparison. Patterns are unique per user by it.
 */
fun RulePattern.isSameAs(other: RulePattern): Boolean = value.equals(other.value, ignoreCase = true)

/**
 * What a rule proposes when it wins: a tag, or a transfer. A transfer has no tag, so a transfer
 * rule with a tag cannot be expressed. See decision 1 in docs/transfer-rules.md.
 */
sealed interface RuleTarget {
    data class Tag(override val tagId: UUID) : RuleTarget

    data object Transfer : RuleTarget {
        override val tagId: UUID? = null
    }

    /** The kind the API and the database name the target by. */
    val kind: Kind
        get() =
            when (this) {
                is Tag -> Kind.Tag
                Transfer -> Kind.Transfer
            }

    /** The tag a tag target proposes; null for a transfer. */
    val tagId: UUID?

    /**
     * A target crosses the API and the database as a kind and an optional tag id, since the OpenAPI
     * document cannot describe a union with fields. See decision 9 in docs/transfer-rules.md.
     */
    enum class Kind {
        Tag,
        Transfer,
    }

    companion object {
        /** The target from its kind and tag id: a tag needs an id and a transfer rejects one. */
        context(_: Raise<String>)
        fun create(kind: String, tagId: UUID?): RuleTarget =
            when (kind) {
                Kind.Tag.name -> Tag(ensureNotNull(tagId) { "A tag target needs a tag id" })
                Kind.Transfer.name -> {
                    ensure(tagId == null) { "A transfer cannot have a tag" }
                    Transfer
                }
                else ->
                    raise(
                        "\"$kind\" is not a valid target, expecting one of \"Tag\" or \"Transfer\"."
                    )
            }
    }
}

data class Rule(val id: UUID, val pattern: RulePattern, val target: RuleTarget)

/** Whether the pattern occurs anywhere in the description under the rule comparison. */
fun RulePattern.matches(description: TransactionDescription): Boolean =
    RulePattern.indexIn(description.value, value) >= 0

/**
 * Rule precedence: longer patterns first, then equal lengths by the rule comparison. The final
 * ordinal step only separates patterns that differ by case alone, which uniqueness rules out, so
 * the order never depends on the order of the input.
 */
private val precedence: Comparator<Rule> =
    compareByDescending<Rule> { it.pattern.value.length }
        .thenComparator { a, b -> a.pattern.value.compareTo(b.pattern.value, ignoreCase = true) }
        .thenBy { it.pattern.value }

/**
 * The winning rule for a description: the matching rule with the longest pattern, whatever its
 * target, with equal lengths ordered by the comparison. Null when no rule matches. Call it once per
 * set of rules and reuse the result for many descriptions, so the rules are sorted once.
 */
fun winner(rules: List<Rule>): (TransactionDescription) -> Rule? {
    val ordered = rules.sortedWith(precedence)
    return { description -> ordered.firstOrNull { it.pattern.matches(description) } }
}
