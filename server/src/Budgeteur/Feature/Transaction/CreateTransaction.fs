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
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.TagAssignment
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating a transaction. The id is generated
    /// server-side.</summary>
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

    /// <summary>Insert the transaction and its assignment, and read it back,
    /// in one database transaction.</summary>
    let private insert
        (queryContext : QueryContextFactory)
        (userId : string)
        (transaction : Transaction)
        (assignment : TagAssignment option)
        =
        task {
            let row = TransactionCodec.toRow transaction userId None

            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! _ =
                insertTask ctx {
                    for t in main.Transactions do
                        entity row
                }

            do! TagAssignmentStore.save ctx userId transaction.Id assignment
            let! created = TransactionQuery.tryRead ctx userId transaction.Id
            ctx.CommitTransaction ()

            return
                created
                |> Result.requireSome (
                    NotFound $"Transaction %O{transaction.Id} not found"
                )
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateTransactionRequest) = Json.read ctx

                let! description =
                    TransactionDescription.create req.Description

                do!
                    TagAssignment.requireNoTagOnTransfer
                        req.IsTransfer
                        req.TagId

                do!
                    Constraints.requireAll [
                        Constraints.requireTagIfReferenced
                            queryContext
                            userId
                            req.TagId
                        Constraints.requireAccountIfReferenced
                            queryContext
                            userId
                            req.AccountId
                    ]

                let transaction : Transaction = {
                    Id = Guid.CreateVersion7 ()
                    Amount = Money.create req.Amount
                    Description = description
                    Date = req.Date
                    IsTransfer = req.IsTransfer
                    AccountId = req.AccountId
                }

                let assignment = TagAssignment.onCreate req.TagId

                let! transaction, assignment, accountName =
                    insert queryContext userId transaction assignment

                log.Info (
                    $"Created transaction %O{transaction.Id}",
                    LogProp.prop "transactionId" (transaction.Id.ToString ())
                )

                ctx.SetStatusCode 201

                do!
                    Json.write
                        ctx
                        (TransactionResponse.fromDomain
                            transaction
                            assignment
                            accountName)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Create a transaction"

        op.Description <-
            "Creates a new transaction and returns it with status 201."

        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]

        Task.CompletedTask

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
                configureOperation = configureOperation
            )
        )
