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

    open Budgeteur.Data
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

    /// <summary>Ensure the tag exists before updating it.</summary>
    let private requireTagExists (queryContext : QueryContextFactory) (userId : string) (id : Guid) =
        task {
            let! rowCount =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.Id = id && t.UserId = userId)
                        count
                }

            return
                if rowCount > 0 then
                    Ok ()
                else
                    Error (NotFound $"The tag {id} could not be found")

        }

    /// <summary>Verify that no other tag with the same name exists for this user, excluding the
    /// tag being updated (the <c>UNIQUE(UserId, Name)</c> constraint).</summary>
    let private requireTagIsUnique (queryContext : QueryContextFactory) (userId : string) (tag : Tag) =
        task {
            let name = TagName.value tag.Name

            let! rowCount =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.Id <> tag.Id && t.Name = name && t.UserId = userId)
                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError $"A tag with the name '{name}' already exists")
        }

    let private update (queryContext : QueryContextFactory) (userId : string) (tag : Tag) =
        task {
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

            return Option.map TagCodec.fromRow result
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateTagRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                do! requireTagExists queryContext userId id
                let! name = TagName.create req.Name
                let tag : Tag = { Id = id; Name = name }

                do! Constraints.requireOne (requireTagIsUnique queryContext userId tag)
                let! updated = update queryContext userId tag

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
