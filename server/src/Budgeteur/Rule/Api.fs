namespace Budgeteur.Rule

/// The main entrypoint for the Rule feature slice
module Api =
    open Oxpecker

    open Budgeteur.Db
    open Budgeteur.Rule.Endpoints.Create
    open Budgeteur.Rule.Endpoints.Delete
    open Budgeteur.Rule.Endpoints.Read
    open Budgeteur.Rule.Endpoints.Update

    let endpoints (ctx : QueryContextFactory) : Oxpecker.RoutingTypes.Endpoint seq = [
        POST [ Create.endpoint ctx ]
        GET [ Read.endpoint ctx ]
        PUT [ Update.endpoint ctx ]
        DELETE [ Delete.endpoint ctx ]
    ]
