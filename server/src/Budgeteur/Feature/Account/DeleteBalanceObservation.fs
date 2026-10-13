namespace Budgeteur.Feature.Account

module DeleteBalanceObservation =
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
    let Path = "/api/accounts/{%O:guid}/observations/{%s}"

    let private parseAsOf (asOf : string) =
        Extra.DateOnly.tryParse asOf
        |> Result.requireSome (
            ValidationFailed
                $"The as-of date must be in the format yyyy-MM-dd, got '{asOf}'"
        )

    /// <summary>Delete the user's account's observation on the date. Deleting
    /// the last one leaves the account's balance unknown.</summary>
    let private delete
        (queryContext : QueryContextFactory)
        (userId : string)
        (accountId : Guid)
        (asOf : DateOnly)
        =
        task {
            let! rows =
                deleteTask queryContext {
                    for o in main.BalanceObservations do
                        where (
                            o.AccountId = accountId
                            && o.UserId = userId
                            && o.AsOf = asOf
                        )
                }

            return rows > 0
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
                let! deleted = delete queryContext userId id asOf

                if deleted then
                    log.Info (
                        $"Deleted the balance on %O{asOf} for account %O{id}",
                        LogProp.prop "accountId" (id.ToString ())
                    )

                    ctx.SetStatusCode 204
                else
                    return!
                        Error (
                            NotFound
                                $"No balance on %O{asOf} for account %O{id}"
                        )
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Delete an account's balance"

        op.Description <-
            "Deletes the balance recorded for the account on a date. The \
            previous balance becomes current; deleting the last leaves the \
            balance unknown. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

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
