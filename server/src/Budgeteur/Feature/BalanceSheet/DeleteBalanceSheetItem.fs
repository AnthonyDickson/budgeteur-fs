namespace Budgeteur.Feature.BalanceSheet

module DeleteBalanceSheetItem =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}"

    let private deleteBalanceSheetItem
        (queryContext : QueryContextFactory)
        (userId : string)
        (id : Guid)
        =
        task {
            let! rows =
                deleteTask queryContext {
                    for t in main.BalanceSheetItems do
                        where (t.Id = id && t.UserId = userId)
                }

            return rows > 0
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! deleted = deleteBalanceSheetItem queryContext userId id

                if deleted then
                    log.Info (
                        $"Deleted balance sheet item %O{id}",
                        LogProp.prop "balanceSheetItemId" (id.ToString ())
                    )

                    ctx.SetStatusCode 204
                else
                    log.Warn (
                        $"Balance sheet item %O{id} not found",
                        LogProp.prop "balanceSheetItemId" (id.ToString ())
                    )

                    return!
                        Error (NotFound $"Balance sheet item %O{id} not found")
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Delete a balance sheet item"

        op.Description <-
            "Permanently removes a balance sheet item. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
