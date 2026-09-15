namespace Budgeteur.Feature.BalanceSheet

module ReadAllBalanceSheetItems =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items"

    let private getAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! items =
                selectTask queryContext {
                    for item in main.BalanceSheetItems do
                        select item
                        where (item.UserId = userId)
                }

            return Seq.map BalanceSheetItemCodec.fromRow items |> List.ofSeq
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! items = getAll queryContext userId

                log.Info (
                    $"Returned %i{List.length items} balance sheet items",
                    LogProp.prop "count" (List.length items)
                )

                let response = List.map BalanceSheetItemResponse.fromDomain items
                do! Json.write ctx response
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetItemResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Get all balance sheet items"
                        op.Description <- "Returns all of the user's balance sheet items."
                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
