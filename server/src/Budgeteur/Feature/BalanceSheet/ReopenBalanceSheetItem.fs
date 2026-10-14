namespace Budgeteur.Feature.BalanceSheet

module ReopenBalanceSheetItem =
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
    let Path = "/api/balance-sheet/items/{%O:guid}/close-date"

    /// <summary>Clear the user's item's close date. Returns whether the user
    /// has an item with the id.</summary>
    let private reopen
        (queryContext : QueryContextFactory)
        (userId : string)
        (itemId : Guid)
        =
        task {
            let closedOn : DateOnly option = None

            let! rows =
                updateTask queryContext {
                    for b in main.BalanceSheetItems do
                        set b.ClosedOn closedOn
                        where (b.Id = itemId && b.UserId = userId)
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

                do!
                    reopen queryContext userId id
                    |> TaskResult.requireTrue (
                        NotFound $"Balance sheet item %O{id} not found"
                    )

                log.Info (
                    $"Reopened balance sheet item %O{id}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Reopen a balance sheet item"

        op.Description <-
            "Clears the item's close date, so every balance sheet includes it \
            again. Returns 204 on success, including for an item that is \
            already open."

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
