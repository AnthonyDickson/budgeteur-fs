namespace Budgeteur.Feature.Tag

open System

module ReadTag =
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
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/tags/{%O:guid}"

    let private get (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            let! result =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.Id = id && t.UserId = userId)
                        tryHead
                }

            let tag = result |> Option.map TagCodec.fromRow

            return tag
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! tag = get queryContext id userId
                let log = RequestLog.fromContext ctx

                match tag with
                | Some tag ->
                    log.Info ($"Returned tag %O{id}", LogProp.prop "tagId" (id.ToString ()))
                    do! Json.write ctx (TagResponse.fromDomain tag)
                | None ->
                    log.Warn ($"Tag %O{id} not found", LogProp.prop "tagId" (id.ToString ()))
                    return! Error (NotFound $"Tag %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<TagResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Get a tag by ID"
                        op.Description <- "Returns a single tag, or 404 if not found."
                        op.Tags <- HashSet [ OpenApiTagReference "Tags" ]
                        Task.CompletedTask
            )
        )
