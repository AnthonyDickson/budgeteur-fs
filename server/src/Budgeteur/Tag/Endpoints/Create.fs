namespace Budgeteur.Tag.Endpoints.Create

/// <summary>Payload for creating a tag. The id is generated server-side.</summary>
type CreateTagRequest = { Name : string }

module Create =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.Data.Sqlite
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
    let Path = "/api/tags"

    let private insert (queryContext : QueryContextFactory) (tag : Tag) (userId : string) =
        task {
            let row = Tag.toRow tag userId

            try
                let! _ =
                    insertTask queryContext {
                        for t in main.Tags do
                            entity row
                    }

                return Ok ()
            with
            | :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
                return Error (Conflict $"A tag with ID %O{tag.Id} already exists")
            | ex -> return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateTagRequest) = Json.read ctx
                let! name = Validation.validateAndTrimName req.Name

                let tag = {
                    Id = Guid.CreateVersion7 ()
                    Name = name
                }

                let! () = insert queryContext tag userId

                log.Info ($"Created tag %O{tag.Id}", LogProp.prop "tagId" (tag.Id.ToString ()))

                ctx.SetStatusCode 201
                do! Json.write ctx tag
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateTagRequest>,
                responseBodies = [|
                    ResponseBody (typeof<Tag>, statusCode = 201)
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
