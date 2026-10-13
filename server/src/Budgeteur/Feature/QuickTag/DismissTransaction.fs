namespace Budgeteur.Feature.QuickTag

module DismissTransaction =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/quick-tag/{%O:guid}"

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                do!
                    QuickTagWrite.save
                        queryContext
                        userId
                        id
                        Categorisation.onDismiss

                log.Info (
                    $"Dismissed transaction %O{id}",
                    LogProp.prop "transactionId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Dismiss a transaction"

        op.Description <-
            "Records that the transaction has no tag, which removes it from \
            the quick tagging queue. Rules never tag a dismissed \
            transaction. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
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
