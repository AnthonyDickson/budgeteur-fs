namespace Budgeteur.Feature.Tag

module UpdateTag =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Tag
    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for updating a tag.</summary>
    type UpdateTagRequest = { Name : string }

    [<Literal>]
    let Path = "/api/tags/{%O:guid}"

    let private update (queryContext : QueryContextFactory) (tag : Tag) (userId : string) =
        task {
            try
                use! shared = queryContext.OpenContextAsync ()
                shared.BeginTransaction ()

                let row = TagCodec.toRow tag userId

                let! _rowsAffected =
                    updateTask shared {
                        for t in main.Tags do
                            entity row
                            excludeColumn t.Id
                            where (t.Id = tag.Id && t.UserId = userId)
                    }

                let! result =
                    selectTask shared {
                        for t in main.Tags do
                            where (t.Id = tag.Id && t.UserId = userId)
                            tryHead
                    }

                shared.CommitTransaction ()

                return Ok (Option.map TagCodec.fromRow result)
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateTagRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                let! name = TagName.create req.Name
                let tag : Tag = { Id = id; Name = name }
                let! updated = update queryContext tag userId

                match updated with
                | Some updated ->
                    log.Info ($"Updated tag %O{id}", LogProp.prop "tagId" (id.ToString ()))
                    do! Json.write ctx (TagResponse.fromDomain updated)
                | None ->
                    log.Warn ($"Tag %O{id} not found", LogProp.prop "tagId" (id.ToString ()))
                    return! Error (NotFound $"Tag %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateTagRequest>,
                responseBodies = [|
                    ResponseBody typeof<TagResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Update a tag"
                        op.Description <- "Replaces the tag."
                        op.Tags <- HashSet [ OpenApiTagReference "Tags" ]
                        Task.CompletedTask
            )
        )
