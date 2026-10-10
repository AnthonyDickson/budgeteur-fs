namespace Budgeteur.Feature.Transaction

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module TransactionEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) = [
        POST [ CreateTransaction.endpoint queryContext ]
        GET [
            ReadTransaction.endpoint queryContext
            ReadAllTransactions.endpoint queryContext
        ]
        PUT [ UpdateTransaction.endpoint queryContext ]
        DELETE [ DeleteTransaction.endpoint queryContext ]
    ]
