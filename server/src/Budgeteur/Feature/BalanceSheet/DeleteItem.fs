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

    let deleteBalanceSheetItem (queryContext : QueryContext) (userId : string) (id : Guid) =
        task {
            let! rows =
                deleteTask queryContext {
                    for t in main.BalanceSheetItems do
                        where (t.Id = id && t.UserId = userId)
                }

            let deleted = rows > 0

            return deleted
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                use! sharedCtx = queryContext.OpenContextAsync ()
                sharedCtx.BeginTransaction ()
                let! deleted = deleteBalanceSheetItem sharedCtx userId id

                if deleted then
                    do! BalanceSheetStore.updateOrCreate sharedCtx DateTime.UtcNow userId
                    sharedCtx.CommitTransaction ()
                    log.Info ($"Deleted balance sheet item %O{id}", LogProp.prop "balanceSheetItemId" (id.ToString ()))
                    ctx.SetStatusCode 204
                else
                    sharedCtx.RollbackTransaction ()

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
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Delete a balance sheet item"
                        op.Description <- "Permanently removes a balance sheet item. Returns 204 on success."
                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
