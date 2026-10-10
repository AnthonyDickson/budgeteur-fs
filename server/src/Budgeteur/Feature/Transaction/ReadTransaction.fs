namespace Budgeteur.Feature.Transaction

open System

module ReadTransaction =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/transactions/{%O:guid}"

    let private get
        (queryContext : QueryContextFactory)
        (userId : string)
        (id : Guid)
        =
        task {
            let! row =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.TagAssignments
                                          on
                                          (t.Id = a.TransactionId)

                        where (t.Id = id && t.UserId = userId)
                        select (t, a)
                        tryHead
                }

            return Option.map TransactionCodec.fromJoinedRow row
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! transaction = get queryContext userId id
                let log = RequestLog.fromContext ctx

                match transaction with
                | Some (transaction, assignment) ->
                    log.Info (
                        $"Returned transaction %O{id}",
                        LogProp.prop "transactionId" (id.ToString ())
                    )

                    do!
                        Json.write
                            ctx
                            (TransactionResponse.fromDomain
                                transaction
                                assignment)
                | None ->
                    log.Warn (
                        $"Transaction %O{id} not found",
                        LogProp.prop "transactionId" (id.ToString ())
                    )

                    return! Error (NotFound $"Transaction %O{id} not found")
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get a transaction by ID"

        op.Description <-
            "Returns a single transaction item, or 404 if not found."

        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<TransactionResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
