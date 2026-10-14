namespace Budgeteur.Feature.BalanceSheet

module CloseBalanceSheetItem =
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
    open Budgeteur.Domain.CloseDate
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for closing a balance sheet item: it was sold or
    /// repaid.</summary>
    type CloseBalanceSheetItemRequest = {
        /// <summary>The date the item was sold or repaid. At most one day after
        /// the server's UTC date. Replaces any earlier close date.</summary>
        ClosedOn : DateOnly
    }

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}/close-date"

    /// <summary>Set the user's item's close date and read it back with its
    /// current value, in one database transaction. Fails with
    /// <c>NotFound</c> when the user has no item with the id.</summary>
    let private close
        (queryContext : QueryContextFactory)
        (userId : string)
        (itemId : Guid)
        (closedOn : DateOnly)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()
            let closedOn = Some closedOn

            let! _ =
                updateTask ctx {
                    for b in main.BalanceSheetItems do
                        set b.ClosedOn closedOn
                        where (b.Id = itemId && b.UserId = userId)
                }

            let! closed = ItemQuery.tryRead ctx userId itemId
            ctx.CommitTransaction ()

            return
                closed
                |> Result.requireSome (
                    NotFound $"Balance sheet item %O{itemId} not found"
                )
        }

    let private handler
        (queryContext : QueryContextFactory)
        (clock : Clock)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CloseBalanceSheetItemRequest) = Json.read ctx
                let! closedOn = CloseDate.validate (clock ()) req.ClosedOn
                let! item = close queryContext userId id closedOn

                log.Info (
                    $"Closed balance sheet item %O{id} on %O{closedOn}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                do! Json.write ctx (BalanceSheetItemResponse.fromDomain item)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Close a balance sheet item"

        op.Description <-
            "Sets the date the item was sold or repaid. Balance sheets drawn \
            on or after it leave the item out; earlier ones keep it. Returns \
            the item with its current value."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CloseBalanceSheetItemRequest>,
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetItemResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
