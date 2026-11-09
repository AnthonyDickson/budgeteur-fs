package budgeteur.domain

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import java.util.UUID

/**
 * Who decided a categorisation, whatever its kind. Re-tag recomputes only [Rule] categorisations;
 * every other source is a decision re-tag never changes. See decision 4 in docs/transfer-rules.md.
 */
enum class Source {
    /** The user decided, without choosing a suggestion. */
    Manual,

    /** The user chose the suggestion, on one row or by approving it. */
    Accepted,

    /** Auto-tagging applied a rule's proposal. */
    Rule,

    /** Import detected a transfer by the other party's account number. */
    Detected,
}

/**
 * How a transaction is categorised, kept apart from the transaction so categorising never changes
 * its facts. An untagged transaction has none, so its categorisation is `null`.
 */
sealed interface Categorisation {
    /** Who decided. A dismissal is always the user's decision. */
    val source: Source

    data class Tagged(val tagId: UUID, override val source: Source) : Categorisation

    /**
     * The user decided the transaction has no tag. No proposal ever dismisses. See decision 1 in
     * docs/quick-tagging.md.
     */
    data object Dismissed : Categorisation {
        override val source = Source.Manual
    }

    /**
     * The transaction moves money between the user's own accounts, so it has no tag and is neither
     * income nor expense.
     */
    data class Transfer(override val source: Source) : Categorisation

    // The transitions between untagged, tagged, dismissed, and transfer. See decision 4 in
    // docs/auto-tagging.md. The rest arrive with the slices that use them.
    companion object {
        /** A transfer is neither income nor expense, so a request cannot give it a tag. */
        context(_: Raise<String>)
        fun requireNoTagOnTransfer(isTransfer: Boolean, tagId: UUID?) =
            ensure(!isTransfer || tagId == null) { "A transfer cannot have a tag" }

        /** A transfer or a tag, set by the user; otherwise untagged. */
        fun onCreate(isTransfer: Boolean, tagId: UUID?): Categorisation? =
            when {
                isTransfer -> Transfer(Source.Manual)
                tagId != null -> Tagged(tagId, Source.Manual)
                else -> null
            }

        /**
         * Keeping a transfer, a dismissal, or the same tag keeps its source, so editing the amount
         * of a rule-tagged transaction does not make it manual and saving a detected transfer keeps
         * it detected. Otherwise the user's choice applies, as on create.
         */
        fun onUpdate(isTransfer: Boolean, tagId: UUID?, current: Categorisation?): Categorisation? {
            val chosen = onCreate(isTransfer, tagId)
            return when (current) {
                is Transfer -> if (isTransfer) current else chosen
                Dismissed -> chosen ?: current
                is Tagged -> if (!isTransfer && tagId == current.tagId) current else chosen
                null -> chosen
            }
        }
    }
}

val Categorisation?.isTransfer: Boolean
    get() = this is Categorisation.Transfer
