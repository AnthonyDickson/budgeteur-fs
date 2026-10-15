namespace Budgeteur.Data

/// <summary>Matches descriptions against a rule pattern in SQL, under the rule
/// comparison, so queries can filter and page by text in the database. SQLite's
/// <c>LIKE</c> folds ASCII case only and treats <c>%</c> and <c>_</c> as
/// wildcards. See decision 2 in docs/transaction-search.md.</summary>
module PatternMatch =
    open System

    open Microsoft.Data.Sqlite
    open SqlHydra.Query

    open Budgeteur.Domain.Rule

    [<Literal>]
    let private Name = "pattern_position"

    /// <summary>Where the pattern first occurs in the description under the
    /// rule comparison, counting from 1, or 0 when it does not occur, like
    /// SQLite's <c>instr</c>. A query matches with <c>&gt; 0</c>. Only for
    /// query expressions: SqlHydra renders the call as SQL, and the connection
    /// must have the function registered.</summary>
    [<SqlHydraFunction(Name)>]
    let position (description : string, pattern : string) : int = sqlFn

    /// <summary>Register the function on the context's connection. Functions
    /// are per connection, so call it on each context a matching query
    /// uses.</summary>
    let register (ctx : QueryContext) =
        let connection = ctx.Connection :?> SqliteConnection

        connection.CreateFunction (
            Name,
            Func<string, string, int>(fun description pattern ->
                description.IndexOf (pattern, RulePattern.comparison) + 1),
            isDeterministic = true
        )
