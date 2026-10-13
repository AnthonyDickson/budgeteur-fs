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
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}"

    let private notFound (id : Guid) =
        NotFound $"Could not find the balance sheet item %O{id}"

    /// <summary>Write the item's details and read it back with its current
    /// value, in one database transaction.</summary>
    let private update
        (queryContext : QueryContextFactory)
        (userId : string)
        (item : BalanceSheetItem)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()
            let row = BalanceSheetItemCodec.toRow item userId

            let! _ =
                updateTask ctx {
                    for b in main.BalanceSheetItems do
                        set b.Name row.Name
                        set b.Term row.Term
                        set b.ClosedOn row.ClosedOn
                        where (b.Id = row.Id && b.UserId = userId)
                }

            let! updated = ItemQuery.tryRead ctx userId item.Id
            ctx.CommitTransaction ()
            return updated |> Result.requireSome (notFound item.Id)
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
                let! (req : UpdateBalanceSheetItemRequest) = Json.read ctx

                use! db = queryContext.OpenContextAsync ()

                let! existing =
                    ItemQuery.tryRead db userId id
                    |> TaskResult.requireSome (notFound id)

                let! item =
                    ItemRequest.validateUpdate (clock ()) existing.Item req

                do!
                    Constraints.requireOne (
                        ItemQuery.requireIsUnique queryContext userId item
                    )

                let! updated = update queryContext userId item

                log.Info (
                    $"Updated balance sheet item %O{id}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                do!
                    Json.write
                        ctx
                        (BalanceSheetItemResponse.fromDomain updated)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Update a balance sheet item"

        op.Description <-
            "Replaces a balance sheet item's name, term, and close date. Its \
            side is fixed at creation, and its values are recorded as \
            observations."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        routef Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateBalanceSheetItemRequest>,
                responseBodies = [|
                    ResponseBody (
                        typeof<BalanceSheetItemResponse>,
                        statusCode = 200
                    )
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
