namespace Budgeteur.Feature.BalanceSheet

module RecordItemObservation =
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
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}/observations"

    /// <summary>Record the value for the user's item and read the item back,
    /// in one database transaction. Fails with <c>NotFound</c> when the user
    /// has no item with the id.</summary>
    let private record
        (queryContext : QueryContextFactory)
        (userId : string)
        (itemId : Guid)
        (observation : ItemObservation)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()
            let notFound = NotFound $"Balance sheet item %O{itemId} not found"

            let! owned =
                selectTask ctx {
                    for b in main.BalanceSheetItems do
                        where (b.Id = itemId && b.UserId = userId)
                        count
                }

            if owned = 0 then
                return Error notFound
            else
                do! ItemObservationStore.record ctx userId itemId observation
                let! recorded = ItemQuery.tryRead ctx userId itemId
                ctx.CommitTransaction ()
                return recorded |> Result.requireSome notFound
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
                let! (req : ItemObservationRequest) = Json.read ctx

                let! observation =
                    ItemRequest.validateObservation (clock ()) req

                let! item = record queryContext userId id observation

                log.Info (
                    $"Recorded a value for balance sheet item %O{id}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                do! Json.write ctx (BalanceSheetItemResponse.fromDomain item)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Record a balance sheet item's value"

        op.Description <-
            "Records the item's value as of a date, replacing any value on \
            that date. Returns the item with its current value: the latest by \
            as-of date, so an older value does not replace a newer one."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<ItemObservationRequest>,
                responseBodies = [|
                    ResponseBody typeof<BalanceSheetItemResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
