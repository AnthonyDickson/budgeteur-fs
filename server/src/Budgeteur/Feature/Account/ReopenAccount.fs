namespace Budgeteur.Feature.Account

module ReopenAccount =
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
    let Path = "/api/accounts/{%O:guid}/close-date"

    /// <summary>Clear the user's account's close date. Returns whether the
    /// user has an account with the id.</summary>
    let private reopen
        (queryContext : QueryContextFactory)
        (userId : string)
        (accountId : Guid)
        =
        task {
            let closedOn : DateOnly option = None

            let! rows =
                updateTask queryContext {
                    for a in main.Accounts do
                        set a.ClosedOn closedOn
                        where (a.Id = accountId && a.UserId = userId)
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
                        NotFound $"Account %O{id} not found"
                    )

                log.Info (
                    $"Reopened account %O{id}",
                    LogProp.prop "accountId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Reopen an account"

        op.Description <-
            "Clears the account's close date, so every balance sheet includes \
            it again. Returns 204 on success, including for an account that is \
            already open."

        op.Tags <- HashSet [ OpenApiTagReference "Accounts" ]

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
