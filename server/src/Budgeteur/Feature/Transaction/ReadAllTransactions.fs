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
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/transactions"

    let private getAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            try
                let! rows =
                    selectTask queryContext {
                        for t in main.Transactions do
                            select t
                            where (t.UserId = userId)
                    }

                let transactions = rows |> List.ofSeq |> List.map Transaction.fromRow

                return Ok transactions
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
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

                do! Json.write ctx transactions
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<Transaction list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "List all transactions"
                        op.Description <- "Returns every transaction in the store."
                        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                        Task.CompletedTask
            )
        )
