namespace Budgeteur.Feature.BalanceSheet

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module BalanceSheetEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) (clock : Clock) = [
        GET [ ReadBalanceSheet.endpoint queryContext ]
        POST [ CreateBalanceSheetItem.endpoint queryContext clock ]
        PUT [ UpdateBalanceSheetItem.endpoint queryContext clock ]
        DELETE [ DeleteBalanceSheetItem.endpoint queryContext clock ]
    ]

    /// <summary>Item reads for manual inspection. Development only, so they are
    /// not advertised as supported API.</summary>
    let developmentOnly (queryContext : QueryContextFactory) = [
        GET [
            ReadBalanceSheetItem.endpoint queryContext
            ReadAllBalanceSheetItems.endpoint queryContext
        ]
    ]
