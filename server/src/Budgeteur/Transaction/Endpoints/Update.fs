namespace Budgeteur.Transaction.Endpoints.Update

open System

/// <summary>Payload for updating a transaction.</summary>
type UpdateTransactionRequest = {
    Amount : decimal
    Description : string
    Date : DateOnly
}

module Update =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.Data.Sqlite
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.ApiError
    open Budgeteur.Auth
    open Budgeteur.Db
    open Budgeteur.DomainError
    open Budgeteur.Endpoint
    open Budgeteur.Json
    open Budgeteur.Money
    open Budgeteur.RequestLogging
    open Budgeteur.Transaction

    [<Literal>]
    let Path = "/api/transactions/{%O:guid}"

    let private update (queryContext : QueryContextFactory) (transaction : Transaction) (userId : string) =
        task {
            try
                use! shared = queryContext.OpenContextAsync ()
                shared.BeginTransaction ()

                let row = Transaction.toRow transaction userId None

                let! _rowsAffected =
                    updateTask shared {
                        for t in main.Transactions do
                            entity row
                            excludeColumn t.Id
                            where (t.Id = transaction.Id && t.UserId = userId)
                    }

                let! result =
                    selectTask shared {
                        for t in main.Transactions do
                            where (t.Id = transaction.Id && t.UserId = userId)
                            tryHead
                    }

                shared.CommitTransaction ()

                let transaction = result |> Option.map Transaction.fromRow

                return Ok transaction
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateTransactionRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                let! description = Validation.validateAndTrimDescription req.Description
                // The URL owns resource identity; the validated body supplies the mutable fields.
                let transaction = {
                    Id = id
                    Amount = Money.roundToCents req.Amount
                    Description = description
                    Date = req.Date
                    AccountId = None
                    CategoryId = None
                }

                let! updated = update queryContext transaction userId

                match updated with
                | Some updated ->
                    log.Info ($"Updated transaction %O{id}", LogProp.prop "transactionId" (id.ToString ()))
                    do! Json.write ctx updated
                | None ->
                    log.Warn ($"Transaction %O{id} not found", LogProp.prop "transactionId" (id.ToString ()))
                    return! Error (NotFound $"Transaction %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateTransactionRequest>,
                responseBodies = [|
                    ResponseBody typeof<Transaction>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Update a transaction"
                        op.Description <- "Replaces the transaction."
                        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                        Task.CompletedTask
            )
        )
