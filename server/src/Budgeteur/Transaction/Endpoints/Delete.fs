namespace Budgeteur.Transaction.Endpoints.Delete

module Delete =
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

    [<Literal>]
    let Path = "/api/transactions/{%O:guid}"

    let delete (queryContext : QueryContextFactory) (id : Guid) (userId : string) =
        task {
            try
                let! rows =
                    deleteTask queryContext {
                        for t in main.Transactions do
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
                    log.Info ($"Deleted transaction %O{id}", LogProp.prop "transactionId" (id.ToString ()))
                    ctx.SetStatusCode 204
                else
                    log.Warn ($"Transaction %O{id} not found", LogProp.prop "transactionId" (id.ToString ()))
                    return! Error (NotFound $"Transaction %O{id} not found")
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
                        op.Summary <- "Delete a transaction"
                        op.Description <- "Permanently removes a transaction. Returns 204 on success."
                        op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                        Task.CompletedTask
            )
        )
