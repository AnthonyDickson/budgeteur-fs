package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure

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
