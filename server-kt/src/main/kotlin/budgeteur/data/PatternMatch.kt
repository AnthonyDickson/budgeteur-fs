package budgeteur.data

import budgeteur.domain.RulePattern
import org.jooq.DSLContext
import org.jooq.Field
import org.jooq.impl.DSL
import org.jooq.impl.SQLDataType
import org.sqlite.Function
import org.sqlite.SQLiteConnection

// Matches descriptions against a rule pattern in SQL, under the rule comparison, so a query can
// filter and page by text in the database. SQLite's LIKE folds ASCII case only and treats % and _
// as wildcards. See decision 2 in docs/transaction-search.md.

private const val NAME = "pattern_position"

/** Where the pattern occurs, counting from 1, or 0, like SQLite's `instr`. */
private class PatternPosition : Function() {
    override fun xFunc() = result(RulePattern.indexIn(value_text(0), value_text(1)) + 1)
}

/** Whether [description] contains [pattern] under the rule comparison. Needs [withPatternMatch]. */
fun containsPattern(description: Field<String?>, pattern: RulePattern) =
    DSL.function(NAME, SQLDataType.INTEGER, description, DSL.value(pattern.value)).gt(0)

/**
 * Runs [work] on one connection with the [containsPattern] function registered. SQLite functions
 * belong to a connection, and outside a transaction jOOQ may take a new connection per query.
 */
fun <T> DSLContext.withPatternMatch(work: DSLContext.() -> T): T = connectionResult { connection ->
    Function.create(
        connection.unwrap(SQLiteConnection::class.java),
        NAME,
        PatternPosition(),
        2,
        Function.FLAG_DETERMINISTIC,
    )
    configuration().derive(connection).dsl().work()
}
