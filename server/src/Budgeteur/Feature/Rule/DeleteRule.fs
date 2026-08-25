namespace Budgeteur.Feature.Rule

module DeleteRule =
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
    let Path = "/api/rules/{%O:guid}"

    let delete (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            try
                let! rows =
                    deleteTask queryContext {
                        for t in main.Rules do
                            where (t.Id = id && t.UserId = userId)
                    }

                let deleted = rows > 0

                return Ok deleted
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! deleted = delete queryContext id userId

                if deleted then
                    log.Info ($"Deleted rule %O{id}", LogProp.prop "ruleId" (id.ToString ()))
                    ctx.SetStatusCode 204
                else
                    log.Warn ($"Rule %O{id} not found", LogProp.prop "ruleId" (id.ToString ()))
                    return! Error (NotFound $"Rule %O{id} not found")
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
                        op.Summary <- "Delete a rule"
                        op.Description <- "Permanently removes a rule. Returns 204 on success."
                        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
                        Task.CompletedTask
            )
        )
