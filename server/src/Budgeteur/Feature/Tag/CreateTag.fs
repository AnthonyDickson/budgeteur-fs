namespace Budgeteur.Feature.Tag

module CreateTag =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.Data.Sqlite
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Tag
    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating a tag. The id is generated server-side.</summary>
    type CreateTagRequest = { Name : string }

    [<Literal>]
    let Path = "/api/tags"

    let private insert (queryContext : QueryContextFactory) (tag : Tag) (userId : string) =
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

                let tag : Tag = {
                    Id = Guid.CreateVersion7 ()
                    Name = tagName
                }

                let! () = insert queryContext tag userId

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
