namespace Budgeteur.Feature.Rule

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by <c>Program.fs</c> and the
/// test host so both route the same handlers.</summary>
module RuleEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) = [
        POST [ CreateRule.endpoint queryContext ]
        GET [ ReadRule.endpoint queryContext; ReadAllRules.endpoint queryContext ]
        PUT [ UpdateRule.endpoint queryContext ]
        DELETE [ DeleteRule.endpoint queryContext ]
    ]
