namespace Budgeteur.Feature.QuickTag

module MarkTransfer =
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
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for marking a transaction as a transfer.</summary>
    type MarkTransferRequest = {
        /// <summary>Whether a transfer was the row's suggestion, so the
        /// transfer records that the user accepted it.</summary>
        Suggested : bool
    }

    [<Literal>]
    let Path = "/api/quick-tag/{%O:guid}/transfer"

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : MarkTransferRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                do!
                    QuickTagWrite.save
                        queryContext
                        userId
                        id
                        (Categorisation.onTransfer req.Suggested)

                log.Info (
                    $"Marked transaction %O{id} as a transfer",
                    LogProp.prop "transactionId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Mark a transaction as a transfer"

        op.Description <-
            "Records that the transaction moves money between the user's own \
            accounts, replacing any categorisation. The source is Accepted \
            when a transfer was the row's suggestion, otherwise Manual. A \
            transfer is neither income nor expense and is not in the quick \
            tagging queue. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<MarkTransferRequest>,
                responseBodies = [|
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
