namespace Budgeteur.Tag

/// The main entrypoint for the Tag feature slice
module Api =
    open Oxpecker

    open Budgeteur.Db
    open Budgeteur.Tag.Endpoints.Create
    open Budgeteur.Tag.Endpoints.Delete
    open Budgeteur.Tag.Endpoints.Read
    open Budgeteur.Tag.Endpoints.Update

    let endpoints (ctx : QueryContextFactory) : Oxpecker.RoutingTypes.Endpoint seq = [
        POST [ Create.endpoint ctx ]
        GET [ Read.endpoint ctx ]
        PUT [ Update.endpoint ctx ]
        DELETE [ Delete.endpoint ctx ]
    ]
