namespace Budgeteur.Feature.Transaction


module UpdateTransaction =
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

    /// <summary>Payload for updating a transaction.</summary>
    type UpdateTransactionRequest = {
        Amount : decimal
        Description : string
        Date : DateOnly
        IsTransfer : bool
        TagId : Guid option
        AccountId : Guid option
    }

    [<Literal>]
    let Path = "/api/transactions/{%O:guid}"

    /// <summary>The user's current assignment for the transaction, if
    /// any.</summary>
    let private readAssignment
        (queryContext : QueryContext)
        (userId : string)
        (id : Guid)
        =
        task {
            let! row =
                selectTask queryContext {
                    for a in main.TagAssignments do
                        where (a.TransactionId = id && a.UserId = userId)
                        tryHead
                }

            return Option.map TagAssignmentCodec.fromRow row
        }

    /// <summary>Replace the user's transaction and set its assignment to the
    /// requested tag, in one database transaction. The current assignment is
    /// read inside the transaction, since keeping the same tag keeps its
    /// source. Fails with <c>NotFound</c> when the user
    /// has no transaction with the id.</summary>
    let private update
        (queryContext : QueryContextFactory)
        (userId : string)
        (transaction : Transaction)
        (tagId : Guid option)
        =
        task {
            let row = TransactionCodec.toRow transaction userId None

            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! rowsAffected =
                updateTask ctx {
                    for t in main.Transactions do
                        entity row
                        excludeColumn t.Id
                        // The request carries no import hash; keeping it lets a
                        // re-import skip the transaction.
                        excludeColumn t.ImportHash
                        where (t.Id = transaction.Id && t.UserId = userId)
                }

            if rowsAffected = 0 then
                return
                    Error (NotFound $"Transaction %O{transaction.Id} not found")
            else
                let! current = readAssignment ctx userId transaction.Id
                let assignment = TagAssignment.onUpdate tagId current
                do! TagAssignmentStore.save ctx userId transaction.Id assignment
                ctx.CommitTransaction ()
                return Ok ()
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateTransactionRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

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
                    Id = id
                    Amount = Money.create req.Amount
                    Description = description
                    Date = req.Date
                    IsTransfer = req.IsTransfer
                    AccountId = req.AccountId
                }

                do! update queryContext userId transaction req.TagId

                log.Info (
                    $"Updated transaction %O{id}",
                    LogProp.prop "transactionId" (id.ToString ())
                )

                match! TransactionQuery.tryRead queryContext userId id with
                | Some (transaction, assignment, accountName) ->
                    do!
                        Json.write
                            ctx
                            (TransactionResponse.fromDomain
                                transaction
                                assignment
                                accountName)
                | None ->
                    return! Error (NotFound $"Transaction %O{id} not found")
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Update a transaction"
        op.Description <- "Replaces the transaction."

        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateTransactionRequest>,
                responseBodies = [|
                    ResponseBody typeof<TransactionResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
