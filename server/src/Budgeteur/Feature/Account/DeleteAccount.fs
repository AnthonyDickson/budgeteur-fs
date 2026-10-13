namespace Budgeteur.Feature.Account

module DeleteAccount =
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
    let Path = "/api/accounts/{%O:guid}"

    /// <summary>Delete the user's account. The schema deletes its balance
    /// observations and transactions with it.</summary>
    let private delete
        (queryContext : QueryContextFactory)
        (userId : string)
        (id : Guid)
        =
        task {
            let! rows =
                deleteTask queryContext {
                    for a in main.Accounts do
                        where (a.Id = id && a.UserId = userId)
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
                let! deleted = delete queryContext userId id

                if deleted then
                    log.Info (
                        $"Deleted account %O{id}",
                        LogProp.prop "accountId" (id.ToString ())
                    )

                    ctx.SetStatusCode 204
                else
                    log.Warn (
                        $"Account %O{id} not found",
                        LogProp.prop "accountId" (id.ToString ())
                    )

                    return! Error (NotFound $"Account %O{id} not found")
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Delete an account"

        op.Description <-
            "Permanently removes an account with its balance history and its \
            transactions. Returns 204 on success."

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
