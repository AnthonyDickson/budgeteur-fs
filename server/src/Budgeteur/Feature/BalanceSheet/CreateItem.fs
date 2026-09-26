namespace Budgeteur.Feature.BalanceSheet

module CreateBalanceSheetItem =
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
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging


    [<Literal>]
    let Path = "/api/balance-sheet/items"

    let private requireBalanceSheetItemIsUnique
        (queryContext : QueryContextFactory)
        (item : BalanceSheetItem)
        (userId : string)
        =
        task {
            let item = BalanceSheetItemCodec.toRow item userId

            let! rowCount =
                selectTask queryContext {
                    for b in main.BalanceSheetItems do
                        where (
                            b.UserId = userId
                            && b.Name = item.Name
                            && b.Kind = item.Kind
                            && b.Term = item.Term
                        )

                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError "An identical balance sheet item already exists.")
        }

    let private insertBalanceSheetItem (queryContext : QueryContext) (item : BalanceSheetItem) (userId : string) =
        task {
            let row = BalanceSheetItemCodec.toRow item userId

            let! _ =
                insertTask queryContext {
                    for b in main.BalanceSheetItems do
                        entity row
                }

            return ()
        }

    let private handler (queryContext : QueryContextFactory) (clock : Clock) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! req = Json.read ctx
                let! item = WriteBalanceSheetItemRequest.validate req (Guid.CreateVersion7 ())

                do! Constraints.requireOne (requireBalanceSheetItemIsUnique queryContext item userId)

                use! sharedCtx = queryContext.OpenContextAsync ()
                sharedCtx.BeginTransaction ()
                do! insertBalanceSheetItem sharedCtx item userId
                do! BalanceSheetStore.updateOrCreate sharedCtx (clock ()) userId
                sharedCtx.CommitTransaction ()

                log.Info (
                    $"Created balance sheet item %O{item.Id}",
                    LogProp.prop "balanceSheetItemId" (item.Id.ToString ())
                )

                ctx.SetStatusCode 201
                do! Json.write ctx (BalanceSheetItemResponse.fromDomain item)
            })

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        route Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<WriteBalanceSheetItemRequest>,
                responseBodies = [|
                    ResponseBody (typeof<BalanceSheetItemResponse>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Create a balance sheet item"

                        op.Description <- "Creates a new balance sheet item, updates the balance sheet statement date"

                        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]
                        Task.CompletedTask
            )
        )
