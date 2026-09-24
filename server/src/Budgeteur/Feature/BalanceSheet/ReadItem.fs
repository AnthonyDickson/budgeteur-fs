namespace Budgeteur.Feature.BalanceSheet

module ReadBalanceSheetItem =
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
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}"

    let private tryReadBalanceSheetItem (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            let! item =
                selectTask queryContext {
                    for item in main.BalanceSheetItems do
                        select item
                        where (item.Id = id && item.UserId = userId)
                        tryHead
                }

            return Option.map BalanceSheetItemCodec.fromRow item
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! item = tryReadBalanceSheetItem queryContext id userId

                match item with
                | Some item ->
                    log.Info (
                        $"Returned balance sheet item %O{id}",
                        LogProp.prop "balanceSheetItemId" (id.ToString ())
                    )

                    do! Json.write ctx (BalanceSheetItemResponse.fromDomain item)
                | None ->
                    log.Warn (
                        $"Balance sheet item %O{id} not found",
                        LogProp.prop "balanceSheetItemId" (id.ToString ())
                    )

                    return! Error (NotFound $"Balance sheet item %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetItemResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Get a balance sheet item"
                        op.Description <- "Returns a user's balance sheet item."
                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
