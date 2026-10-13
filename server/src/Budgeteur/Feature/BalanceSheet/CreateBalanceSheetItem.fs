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
    open Budgeteur.Shared.Clock
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items"

    /// <summary>Insert the item and its first observation and read it back,
    /// in one database transaction.</summary>
    let private insert
        (queryContext : QueryContextFactory)
        (userId : string)
        (item : BalanceSheetItem)
        (first : ItemObservation)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! _ =
                insertTask ctx {
                    for b in main.BalanceSheetItems do
                        entity (BalanceSheetItemCodec.toRow item userId)
                }

            do! ItemObservationStore.record ctx userId item.Id first
            let! created = ItemQuery.tryRead ctx userId item.Id
            ctx.CommitTransaction ()

            return
                created
                |> Result.requireSome (
                    NotFound $"Balance sheet item %O{item.Id} not found"
                )
        }

    let private handler
        (queryContext : QueryContextFactory)
        (clock : Clock)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateBalanceSheetItemRequest) = Json.read ctx

                let! item, first =
                    ItemRequest.validateCreate
                        (clock ())
                        req
                        (Guid.CreateVersion7 ())

                do!
                    Constraints.requireOne (
                        ItemQuery.requireIsUnique queryContext userId item
                    )

                let! created = insert queryContext userId item first

                log.Info (
                    $"Created balance sheet item %O{item.Id}",
                    LogProp.prop "balanceSheetItemId" (item.Id.ToString ())
                )

                ctx.SetStatusCode 201

                do!
                    Json.write
                        ctx
                        (BalanceSheetItemResponse.fromDomain created)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Create a balance sheet item"

        op.Description <-
            "Creates a balance sheet item with its first value and returns it \
            with status 201."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) (clock : Clock) =
        route Path (handler queryContext clock)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateBalanceSheetItemRequest>,
                responseBodies = [|
                    ResponseBody (
                        typeof<BalanceSheetItemResponse>,
                        statusCode = 201
                    )
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
