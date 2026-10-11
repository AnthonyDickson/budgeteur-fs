namespace Budgeteur.Feature.Account

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by
/// <c>Program.fs</c> and the test host so both route the same
/// handlers.</summary>
module AccountEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db
    open Budgeteur.Shared.Clock

    let all (queryContext : QueryContextFactory) (clock : Clock) = [
        POST [ CreateAccount.endpoint queryContext clock ]
        GET [
            ReadAccount.endpoint queryContext
            ReadAllAccounts.endpoint queryContext
        ]
        PUT [ UpdateAccount.endpoint queryContext clock ]
        DELETE [ DeleteAccount.endpoint queryContext ]
    ]
