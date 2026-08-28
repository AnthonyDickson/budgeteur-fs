namespace Budgeteur.Feature.Tag

module DeleteTag =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/tags/{%O:guid}"

    let delete (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            let! rows =
                deleteTask queryContext {
                    for t in main.Tags do
                        where (t.Id = id && t.UserId = userId)
                }

            let deleted = rows > 0

            return deleted
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! deleted = delete queryContext id userId

                if deleted then
                    log.Info ($"Deleted tag %O{id}", LogProp.prop "tagId" (id.ToString ()))
                    ctx.SetStatusCode 204
                else
                    log.Warn ($"Tag %O{id} not found", LogProp.prop "tagId" (id.ToString ()))
                    return! Error (NotFound $"Tag %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody (typeof<unit>, statusCode = 204)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Delete a tag"
                        op.Description <- "Permanently removes a tag. Returns 204 on success."
                        op.Tags <- HashSet [ OpenApiTagReference "Tags" ]
                        Task.CompletedTask
            )
        )
