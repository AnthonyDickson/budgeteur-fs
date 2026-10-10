namespace Budgeteur.Feature.Tag

/// <summary>The slice's endpoints, grouped by HTTP method. Shared by <c>Program.fs</c> and the
/// test host so both route the same handlers.</summary>
module TagEndpoints =
    open Oxpecker

    open Budgeteur.Data.Db

    let all (queryContext : QueryContextFactory) = [
        POST [ CreateTag.endpoint queryContext ]
        GET [ ReadTag.endpoint queryContext; ReadAllTags.endpoint queryContext ]
        PUT [ UpdateTag.endpoint queryContext ]
        DELETE [ DeleteTag.endpoint queryContext ]
    ]
