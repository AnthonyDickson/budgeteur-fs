namespace Budgeteur.Feature.BalanceSheet

module UpdateBalanceSheetItem =
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
    open Budgeteur.Domain.BalanceSheetItem
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}"

    let private requireBalanceSheetItemIsUnique
        (queryContext : QueryContextFactory)
        (item : BalanceSheetItem)
        (userId : string)
        =
        task {
            let item = BalanceSheetItemCodec.toRow item userId

            let! rowCount =
                selectTask queryContext {
                    for row in main.BalanceSheetItems do
                        where (
                            row.Id <> item.Id
                            && row.UserId = item.UserId
                            && row.Name = item.Name
                            && row.Kind = item.Kind
                            && row.Term = item.Term
                        )

                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError "An identical balance sheet item already exists.")
        }

    let private updateBalanceSheetItem (queryContext : QueryContext) (item : BalanceSheetItem) (userId : string) =
        task {
            let row = BalanceSheetItemCodec.toRow item userId

            let! rowsUpdated =
                updateTask queryContext {
                    for b in main.BalanceSheetItems do
                        entity row
                        where (b.Id = row.Id && b.UserId = userId)
                }

            if rowsUpdated = 0 then
                return Error (NotFound $"Could not find the balance sheet item %O{item.Id}")
            else
                return Ok ()
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! req = Json.read ctx
                let! item = WriteBalanceSheetItemRequest.validate req id

                do! Constraints.requireOne (requireBalanceSheetItemIsUnique queryContext item userId)

                use! sharedCtx = queryContext.OpenContextAsync ()
                sharedCtx.BeginTransaction ()
                do! updateBalanceSheetItem sharedCtx item userId
                do! BalanceSheetStore.updateOrCreate sharedCtx DateTime.UtcNow userId
                sharedCtx.CommitTransaction ()

                log.Info (
                    $"Updated balance sheet item %O{item.Id}",
                    LogProp.prop "balanceSheetItemId" (item.Id.ToString ())
                )

                do! Json.write ctx (BalanceSheetItemResponse.fromDomain item)
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<WriteBalanceSheetItemRequest>,
                responseBodies = [|
                    ResponseBody (typeof<BalanceSheetItemResponse>, statusCode = 200)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Update a balance sheet item"

                        op.Description <- "Update a balance sheet item and the balance sheet statement date."

                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
