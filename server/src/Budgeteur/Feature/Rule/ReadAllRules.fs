namespace Budgeteur.Feature.Rule

module ReadAllRules =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/rules"

    let private getAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Rules do
                        select t
                        where (t.UserId = userId)
                }

            let rules = rows |> List.ofSeq |> List.map RuleCodec.fromRow

            return rules
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! rules = getAll queryContext userId

                let log = RequestLog.fromContext ctx

                log.Info ($"Returned %i{List.length rules} rules", LogProp.prop "count" (List.length rules))

                let response = List.map RuleResponse.fromDomain rules
                do! Json.write ctx response
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<RuleResponse list>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "List all rules"
                        op.Description <- "Returns all of the user's rules."
                        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
                        Task.CompletedTask
            )
        )
