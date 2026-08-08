namespace Budgeteur.Transaction

/// The main entrypoint for the Transaction feature slice
module Api =
    open Oxpecker

    open Budgeteur.Auth
    open Budgeteur.Db
    open Budgeteur.Transaction.Endpoints.Create
    open Budgeteur.Transaction.Endpoints.Delete
    open Budgeteur.Transaction.Endpoints.Read
    open Budgeteur.Transaction.Endpoints.ReadAll
    open Budgeteur.Transaction.Endpoints.Update

    let endpoints (ctx : QueryContextFactory) : Oxpecker.RoutingTypes.Endpoint seq = [
        POST [ Create.endpoint ctx ]
        GET [ Read.endpoint ctx; ReadAll.endpoint ctx ]
        PUT [ Update.endpoint ctx ]
        DELETE [ Delete.endpoint ctx ]
    ]
