namespace Budgeteur.Feature.Rule

open System

module ReadRule =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Feature.Rule
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/rules/{%O:guid}"

    let private get (queryContext : QueryContextFactory) (userId : string) (id : Guid) =
        task {
            let! result =
                selectTask queryContext {
                    for t in main.Rules do
                        where (t.Id = id && t.UserId = userId)
                        tryHead
                }

            let rule = result |> Option.map RuleCodec.fromRow

            return rule
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! rule = get queryContext userId id
                let log = RequestLog.fromContext ctx

                match rule with
                | Some rule ->
                    log.Info ($"Returned rule %O{id}", LogProp.prop "ruleId" (id.ToString ()))
                    do! Json.write ctx (RuleResponse.fromDomain rule)
                | None ->
                    log.Warn ($"Rule %O{id} not found", LogProp.prop "ruleId" (id.ToString ()))
                    return! Error (NotFound $"Rule %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<RuleResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Get a rule by ID"
                        op.Description <- "Returns a single rule, or 404 if not found."
                        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
                        Task.CompletedTask
            )
        )
