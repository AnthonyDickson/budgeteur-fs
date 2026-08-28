namespace Budgeteur.Feature.Transaction

module CreateTransaction =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.Money
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating a transaction. The id is generated server-side.</summary>
    type CreateTransactionRequest = {
        Amount : decimal
        Description : string
        Date : DateOnly
        IsTransfer : bool
        TagId : Guid option
        AccountId : Guid option
    }

    [<Literal>]
    let Path = "/api/transactions"

    /// <summary>Verify that the referenced account exists and belongs to the user. Skips the
    /// check when no account is referenced (<c>None</c> succeeds).</summary>
    let private requireAccountExists (queryContext : QueryContextFactory) (userId : string) (accountId : Guid option) =
        task {
            match accountId with
            | Some accountId ->
                let! rowCount =
                    selectTask queryContext {
                        for t in main.Accounts do
                            where (t.Id = accountId && t.UserId = userId)
                            count
                    }

                return
                    if rowCount > 0 then
                        Ok ()
                    else
                        Error (ConstraintError $"Could not find an account with the ID {accountId}")
            | None -> return Ok ()
        }

    let private insert (queryContext : QueryContextFactory) (transaction : Transaction) (userId : string) =
        task {
            let row = TransactionCodec.toRow transaction userId None

            let! _ =
                insertTask queryContext {
                    for t in main.Transactions do
                        entity row
                }

            ()
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateTransactionRequest) = Json.read ctx

                let! description = TransactionDescription.create req.Description

                do!
                    Constraints.requireAll [
                        Constraints.requireTagIfReferenced queryContext userId req.TagId
                        requireAccountExists queryContext userId req.AccountId
                    ]

                let transaction : Transaction = {
                    Id = Guid.CreateVersion7 ()
                    Amount = Money.roundToCents req.Amount
                    Description = description
                    Date = req.Date
                    IsTransfer = req.IsTransfer
                    AccountId = req.AccountId
                    TagId = req.TagId
                }

                let! () = insert queryContext transaction userId

                log.Info (
                    $"Created transaction %O{transaction.Id}",
                    LogProp.prop "transactionId" (transaction.Id.ToString ())
                )

                ctx.SetStatusCode 201
                do! Json.write ctx (TransactionResponse.fromDomain transaction)
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateTransactionRequest>,
                responseBodies = [|
                    ResponseBody (typeof<TransactionResponse>, statusCode = 201)
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
