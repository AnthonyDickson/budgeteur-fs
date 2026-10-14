namespace Budgeteur.Feature.BalanceSheet

module DeleteItemObservation =
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
    open Budgeteur.Shared.Coders
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/balance-sheet/items/{%O:guid}/observations/{%s}"

    let private parseAsOf (asOf : string) =
        Extra.DateOnly.tryParse asOf
        |> Result.requireSome (
            ValidationFailed
                $"The as-of date must be in the format yyyy-MM-dd, got '{asOf}'"
        )

    /// <summary>Delete the user's item's observation on the date, in one
    /// database transaction with the checks. An item always has a known value,
    /// so its last observation is not deleted: the item is deleted
    /// instead.</summary>
    let private delete
        (queryContext : QueryContextFactory)
        (userId : string)
        (itemId : Guid)
        (asOf : DateOnly)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! dates =
                selectTask ctx {
                    for o in main.ItemObservations do
                        where (o.ItemId = itemId && o.UserId = userId)
                        select o.AsOf
                }

            let dates = List.ofSeq dates

            if not (List.contains asOf dates) then
                return
                    Error (
                        NotFound
                            $"No value on %O{asOf} for balance sheet item \
                            %O{itemId}"
                    )
            elif List.length dates = 1 then
                return
                    Error (
                        ValidationFailed
                            "This is the item's only value. An item always has \
                            a value, so delete the item instead."
                    )
            else
                let! _ =
                    deleteTask ctx {
                        for o in main.ItemObservations do
                            where (
                                o.ItemId = itemId
                                && o.UserId = userId
                                && o.AsOf = asOf
                            )
                    }

                ctx.CommitTransaction ()
                return Ok ()
        }

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid, asOf : string)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! asOf = parseAsOf asOf
                do! delete queryContext userId id asOf

                log.Info (
                    $"Deleted the value on %O{asOf} for balance sheet item \
                    %O{id}",
                    LogProp.prop "balanceSheetItemId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Delete a balance sheet item's value"

        op.Description <-
            "Deletes the value recorded for the item on a date, and the \
            previous value becomes current. An item's only value cannot be \
            deleted: delete the item instead. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Balance Sheets" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (fun id asOf -> handler queryContext (id, asOf))
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
