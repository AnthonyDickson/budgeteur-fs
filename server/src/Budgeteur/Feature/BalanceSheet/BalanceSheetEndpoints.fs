namespace Budgeteur.Feature.BalanceSheet

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module BalanceSheetEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db
    open Budgeteur.Shared.Clock

    let all (queryContext : QueryContextFactory) (clock : Clock) = [
        GET [
            ReadBalanceSheet.endpoint queryContext
            ReadBalanceSheetItem.endpoint queryContext
            ReadItemObservations.endpoint queryContext
        ]
        POST [
            CreateBalanceSheetItem.endpoint queryContext clock
            RecordItemObservation.endpoint queryContext clock
        ]
        PUT [ UpdateBalanceSheetItem.endpoint queryContext clock ]
        DELETE [
            DeleteBalanceSheetItem.endpoint queryContext
            DeleteItemObservation.endpoint queryContext
        ]
    ]

    /// <summary>The item list, for manual inspection. Development only, so it
    /// is not advertised as supported API.</summary>
    let developmentOnly (queryContext : QueryContextFactory) = [
        GET [ ReadAllBalanceSheetItems.endpoint queryContext ]
    ]
