namespace Budgeteur.Feature.QuickTag

module QuickTagTransaction =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for quick tagging a transaction.</summary>
    type QuickTagRequest = {
        /// <summary>The tag to give the transaction.</summary>
        TagId : Guid
    }

    [<Literal>]
    let Path = "/api/quick-tag/{%O:guid}"

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : QuickTagRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                do!
                    Constraints.requireOne (
                        Constraints.requireTagExists
                            queryContext
                            userId
                            req.TagId
                    )

                do!
                    QuickTagWrite.save
                        queryContext
                        userId
                        id
                        (Categorisation.onQuickTag req.TagId)

                log.Info (
                    $"Quick tagged transaction %O{id}",
                    LogProp.prop "transactionId" (id.ToString ())
                )

                ctx.SetStatusCode 204
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Quick tag a transaction"

        op.Description <-
            "Gives the transaction the tag as a manual tag, replacing any tag \
            or dismissal it had. Returns 204 on success."

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<QuickTagRequest>,
                responseBodies = [|
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
