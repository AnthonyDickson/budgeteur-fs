namespace Budgeteur.Feature.Tag

module CreateTag =
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
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating a tag. The id is generated server-side.</summary>
    type CreateTagRequest = { Name : string; Color : string }

    [<Literal>]
    let Path = "/api/tags"

    /// <summary>Verify that no tag with the same name exists for this user
    /// (the <c>UNIQUE(UserId, Name)</c> constraint).</summary>
    let private requireNameIsUnique (queryContext : QueryContextFactory) (userId : string) (tagName : TagName) =
        task {
            let name = TagName.value tagName

            let! rowCount =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.Name = name && t.UserId = userId)
                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError $"A tag with the name '{name}' already exists")
        }

    let private insert (queryContext : QueryContextFactory) (userId : string) (tag : Tag) =
        task {
            let row = TagCodec.toRow tag userId

            let! _ =
                insertTask queryContext {
                    for t in main.Tags do
                        entity row
                }

            return ()
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateTagRequest) = Json.read ctx

                let! tagName = TagName.create req.Name
                let! tagColor = TagColor.create req.Color
                do! Constraints.requireOne (requireNameIsUnique queryContext userId tagName)

                let tag : Tag = {
                    Id = Guid.CreateVersion7 ()
                    Name = tagName
                    Color = tagColor
                }

                let! () = insert queryContext userId tag

                log.Info ($"Created tag %O{tag.Id}", LogProp.prop "tagId" (tag.Id.ToString ()))

                ctx.SetStatusCode 201
                do! Json.write ctx (TagResponse.fromDomain tag)
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateTagRequest>,
                responseBodies = [|
                    ResponseBody (typeof<TagResponse>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Create a tag"
                        op.Description <- "Creates a new tag and returns it with status 201."
                        op.Tags <- HashSet [ OpenApiTagReference "Tags" ]
                        Task.CompletedTask
            )
        )
