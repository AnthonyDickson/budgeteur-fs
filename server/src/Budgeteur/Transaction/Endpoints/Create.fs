namespace Budgeteur.Transaction.Endpoints.Create

open System

/// <summary>Payload for creating a transaction. The id is generated server-side.</summary>
type CreateTransactionRequest = {
    Amount : decimal
    Description : string
    Date : DateOnly
    IsTransfer : bool
}

module Create =
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
    let Path = "/api/transactions"

    let private insert (queryContext : QueryContextFactory) (transaction : Transaction) (userId : string) =
        task {
            let row = Transaction.toRow transaction userId None

            try
                let! _ =
                    insertTask queryContext {
                        for t in main.Transactions do
                            entity row
                    }

                return Ok ()
            with
            | :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
                return Error (Conflict $"A transaction with ID %O{transaction.Id} already exists")
            | ex -> return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateTransactionRequest) = Json.read ctx
                let! description = Validation.validateAndTrimDescription req.Description

                let transaction = {
                    Id = Guid.CreateVersion7 ()
                    Amount = Money.roundToCents req.Amount
                    Description = description
                    Date = req.Date
                    IsTransfer = req.IsTransfer
                    AccountId = None
                    CategoryId = None
                }

                let! () = insert queryContext transaction userId

                log.Info (
                    $"Created transaction %O{transaction.Id}",
                    LogProp.prop "transactionId" (transaction.Id.ToString ())
                )

                ctx.SetStatusCode 201
                do! Json.write ctx transaction
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateTransactionRequest>,
                responseBodies = [|
                    ResponseBody (typeof<Transaction>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Create a transaction"
                        op.Description <- "Creates a new transaction and returns it with status 201."
                        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                        Task.CompletedTask
            )
        )
