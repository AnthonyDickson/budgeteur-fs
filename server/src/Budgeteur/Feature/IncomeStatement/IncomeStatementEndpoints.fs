namespace Budgeteur.Feature.IncomeStatement

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module IncomeStatementEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) = [
        GET [ ReadIncomeStatement.endpoint queryContext ]
    ]
