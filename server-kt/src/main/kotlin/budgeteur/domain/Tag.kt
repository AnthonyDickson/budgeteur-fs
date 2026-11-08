package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import arrow.core.raise.context.ensureNotNull
import java.util.UUID

/**
 * A trimmed, non-blank name of at most [MAX_LENGTH] characters. The private
 * constructor means the only way to get one from untrusted input is [create].
 */
@JvmInline
value class TagName private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 64

        context(_: Raise<String>)
        fun create(raw: String): TagName {
            val name = raw.trim()
            ensure(name.isNotEmpty()) { "Tag name cannot be null or whitespace" }
            ensure(name.length <= MAX_LENGTH) {
                "Name is too long. Names must be at most $MAX_LENGTH characters, but got ${name.length}"
            }
            return TagName(name)
        }

        /** Skips validation, for trusted values read from the database. */
        internal fun unsafe(value: String) = TagName(value)
    }
}

/**
 * A tag's colour: one of Catppuccin's accent colours, by name. The client draws
 * it in the active flavour's value. Declared in Catppuccin's order.
 */
enum class TagColor {
    Rosewater, Flamingo, Pink, Mauve, Red, Maroon, Peach,
    Yellow, Green, Teal, Sky, Sapphire, Blue, Lavender;

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): TagColor =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for TagColor, expecting one of ${entries.joinToString(", ")}."
            }
    }
}

/** Which side of the income statement a tag's transactions are on. */
enum class TagKind {
    Income, Expense;

    companion object {
        context(_: Raise<String>)
        fun parse(raw: String): TagKind =
            ensureNotNull(entries.find { it.name == raw }) {
                "\"$raw\" is not a valid value for TagKind, expecting one of \"Income\" or \"Expense\"."
            }
    }
}

data class Tag(
    val id: UUID,
    val name: TagName,
    val color: TagColor,
    val kind: TagKind,
)
