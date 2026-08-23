namespace Budgeteur.Tag.Endpoints.Read

open System

module Read =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.ApiError
    open Budgeteur.Auth
    open Budgeteur.Db
    open Budgeteur.DomainError
    open Budgeteur.Endpoint
    open Budgeteur.Json
    open Budgeteur.RequestLogging
    open Budgeteur.Tag

    [<Literal>]
    let Path = "/api/tags/{%O:guid}"

    let private get (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            try
                let! result =
                    selectTask queryContext {
                        for t in main.Tags do
                            where (t.Id = id && t.UserId = userId)
                            tryHead
                    }

                let tag = result |> Option.map Tag.fromRow

                return Ok tag
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
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
                    do! Json.write ctx tag
                | None ->
                    log.Warn ($"Tag %O{id} not found", LogProp.prop "tagId" (id.ToString ()))
                    return! Error (NotFound $"Tag %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<Tag>
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
