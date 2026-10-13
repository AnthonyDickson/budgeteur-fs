namespace Budgeteur.Feature.QuickTag

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module QuickTagEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) = [
        GET [ ReadQueue.endpoint queryContext ]
        PUT [ QuickTagTransaction.endpoint queryContext ]
        DELETE [ DismissTransaction.endpoint queryContext ]
    ]
