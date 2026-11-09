package budgeteur.feature.rule

import arrow.core.raise.Raise
import arrow.core.raise.context.ensure
import budgeteur.data.ConstraintError
import budgeteur.data.readRules
import budgeteur.domain.Rule
import budgeteur.domain.isSameAs
import org.jooq.DSLContext

/**
 * The `UNIQUE (user_id, pattern COLLATE NOCASE)` constraint, ignoring the rule itself. NOCASE folds
 * ASCII only, so the patterns are compared here under the rule comparison.
 */
context(_: Raise<ConstraintError>)
fun DSLContext.requireUniquePattern(userId: String, rule: Rule) =
    ensure(readRules(userId).none { it.id != rule.id && it.pattern.isSameAs(rule.pattern) }) {
        ConstraintError("A rule with the pattern '${rule.pattern.value}' already exists")
    }
