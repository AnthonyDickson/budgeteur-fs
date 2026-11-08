package budgeteur.domain

import arrow.core.Either
import arrow.core.left
import arrow.core.right
import java.util.UUID

/**
 * A trimmed, non-blank name of at most [MAX_LENGTH] characters. The private
 * constructor means the only way to get one from untrusted input is [create].
 */
@JvmInline
value class TagName private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 64

        fun create(raw: String): Either<String, TagName> {
            val name = raw.trim()
            return when {
                name.isEmpty() -> "Tag name cannot be null or whitespace".left()
                name.length > MAX_LENGTH ->
                    "Name is too long. Names must be at most $MAX_LENGTH characters, but got ${name.length}".left()
                else -> TagName(name).right()
            }
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
        fun parse(raw: String): Either<String, TagColor> =
            entries.find { it.name == raw }?.right()
                ?: "\"$raw\" is not a valid value for TagColor, expecting one of ${entries.joinToString(", ")}.".left()
    }
}

/** Which side of the income statement a tag's transactions are on. */
enum class TagKind {
    Income, Expense;

    companion object {
        fun parse(raw: String): Either<String, TagKind> =
            entries.find { it.name == raw }?.right()
                ?: "\"$raw\" is not a valid value for TagKind, expecting one of \"Income\" or \"Expense\".".left()
    }
}

data class Tag(
    val id: UUID,
    val name: TagName,
    val color: TagColor,
    val kind: TagKind,
)
