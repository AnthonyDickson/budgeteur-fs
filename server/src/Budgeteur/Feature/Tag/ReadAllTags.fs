namespace Budgeteur.Feature.Tag

module ReadAllTags =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/tags"

    let private getAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Tags do
                        select t
                        where (t.UserId = userId)
                }

            let rules = rows |> List.ofSeq |> List.map TagCodec.fromRow

            return rules
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! tags = getAll queryContext userId

                let log = RequestLog.fromContext ctx

                log.Info ($"Returned %i{List.length tags} tags", LogProp.prop "count" (List.length tags))

                let response = List.map TagResponse.fromDomain tags
                do! Json.write ctx response
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<TagResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "List all tags"
                        op.Description <- "Returns all of the user's tags."
                        op.Tags <- HashSet [ OpenApiTagReference "Tags" ]
                        Task.CompletedTask
            )
        )
