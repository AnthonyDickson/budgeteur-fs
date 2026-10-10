namespace Budgeteur.Feature.AutoTag

/// <summary>What a pattern matches among the user's transactions.</summary>
type MatchesResponse = {
    /// <summary>How many of the user's non-transfer transactions the pattern
    /// matches.</summary>
    Count : int

    /// <summary>Up to five distinct descriptions from the most recent matches,
    /// most recent first.</summary>
    Samples : string list
}

module ReadMatches =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Rule
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/auto-tag/matches"

    /// <summary>The descriptions of the user's transactions that may have a
    /// tag, which excludes transfers, most recent first.</summary>
    let private loadDescriptions
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        task {
            let! descriptions =
                selectTask queryContext {
                    for t in main.Transactions do
                        where (t.UserId = userId && not t.IsTransfer)
                        orderByDescending t.Date
                        thenByDescending t.Id
                        select t.Description
                }

            return
                descriptions
                |> Seq.map TransactionDescription.unsafeFromString
                |> List.ofSeq
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! pattern =
                    RulePattern.create (string ctx.Request.Query["pattern"])

                let! descriptions = loadDescriptions queryContext userId
                let matches = AutoTag.matches pattern descriptions

                log.Info (
                    $"Pattern matched %i{matches.Count} transactions",
                    LogProp.prop "count" matches.Count
                )

                do!
                    Json.write ctx {
                        Count = matches.Count
                        Samples =
                            List.map
                                TransactionDescription.value
                                matches.Samples
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get the transactions a pattern matches"

        op.Description <-
            "Returns how many of the user's transactions a rule pattern \
            matches, ignoring case, with sample descriptions. Transfers are \
            excluded. The pattern is validated like a rule pattern."

        op.Parameters <-
            ResizeArray [
                OpenApiParameter (
                    Name = "pattern",
                    In = Nullable ParameterLocation.Query,
                    Required = true,
                    Description = "The rule pattern, e.g. COUNTDOWN.",
                    Schema =
                        OpenApiSchema (Type = Nullable JsonSchemaType.String)
                )
                :> IOpenApiParameter
            ]

        op.Tags <- HashSet [ OpenApiTagReference "Auto-tagging" ]
        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<MatchesResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
