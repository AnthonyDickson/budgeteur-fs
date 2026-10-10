namespace Budgeteur.Feature.Transaction

module ReadAllTransactions =
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
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/transactions"

    let private getAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.TagAssignments
                                          on
                                          (t.Id = a.TransactionId)

                        where (t.UserId = userId)
                        select (t, a)
                }

            return rows |> Seq.map TransactionCodec.fromJoinedRow |> List.ofSeq
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! transactions = getAll queryContext userId

                let log = RequestLog.fromContext ctx

                log.Info (
                    $"Returned %i{List.length transactions} transactions",
                    LogProp.prop "count" (List.length transactions)
                )

                let response =
                    List.map
                        (fun (transaction, assignment) ->
                            TransactionResponse.fromDomain
                                transaction
                                assignment)
                        transactions

                do! Json.write ctx response
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "List all transactions"

        op.Description <- "Returns every transaction in the store."

        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<TransactionResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
