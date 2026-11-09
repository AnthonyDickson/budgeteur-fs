package budgeteur.data

import budgeteur.data.db.tables.records.RulesRecord
import budgeteur.data.db.tables.references.RULES
import budgeteur.domain.Rule
import budgeteur.domain.RulePattern
import budgeteur.domain.RuleTarget
import org.jooq.DSLContext

fun Rule.toRecord(userId: String) =
    RulesRecord(
        id = id,
        userId = userId,
        pattern = pattern.value,
        target = target.kind.name,
        tagId = target.tagId,
    )

/** The database checks that a tag rule, and only a tag rule, has a tag id. */
fun RulesRecord.toRule(): Rule =
    Rule(
        id = id,
        pattern = RulePattern.unsafe(pattern),
        target =
            when (RuleTarget.Kind.valueOf(target)) {
                RuleTarget.Kind.Tag -> RuleTarget.Tag(checkNotNull(tagId))
                RuleTarget.Kind.Transfer -> RuleTarget.Transfer
            },
    )

/** The user's rules, by pattern. Shared by the slices that apply them. */
fun DSLContext.readRules(userId: String): List<Rule> =
    selectFrom(RULES).where(RULES.USER_ID.eq(userId)).orderBy(RULES.PATTERN).fetch { it.toRule() }
