namespace Budgeteur.Feature.BalanceSheet

open System

open Budgeteur.Shared.OpenApi

/// <summary>A value recorded for an item.</summary>
type ItemObservationResponse = {
    /// <summary>The positive magnitude of the item's value. Direction is
    /// implied by the item's side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Value : decimal

    /// <summary>The date the value is accurate as of.</summary>
    AsOf : DateOnly
}

module ReadItemObservations =
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
    let Path = "/api/balance-sheet/items/{%O:guid}/observations"

    /// <summary>The user's item's observations, newest first, or none when the
    /// user has no item with the id.</summary>
    let private read
        (queryContext : QueryContextFactory)
        (userId : string)
        (itemId : Guid)
        =
        task {
            let! owned =
                selectTask queryContext {
                    for b in main.BalanceSheetItems do
                        where (b.Id = itemId && b.UserId = userId)
                        count
                }

            if owned = 0 then
                return None
            else
                let! rows =
                    selectTask queryContext {
                        for o in main.ItemObservations do
                            where (o.ItemId = itemId && o.UserId = userId)
                            orderByDescending o.AsOf
                    }

                return
                    rows
                    |> Seq.map ItemObservationCodec.fromRow
                    |> List.ofSeq
                    |> Some
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! observations =
                    read queryContext userId id
                    |> TaskResult.requireSome (
                        NotFound $"Balance sheet item %O{id} not found"
                    )

                log.Info (
                    $"Returned %i{List.length observations} values for balance \
                    sheet item %O{id}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                do!
                    observations
                    |> List.map (fun observation ->
                        ({
                            Value = Value.value observation.Value
                            AsOf = observation.AsOf
                        }
                        : ItemObservationResponse))
                    |> Json.write ctx
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "List a balance sheet item's values"

        op.Description <-
            "Returns every value recorded for the item, newest first. The \
            first is the current value."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<ItemObservationResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
