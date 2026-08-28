namespace Budgeteur.Feature.Rule

module UpdateRule =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Rule
    open Budgeteur.Feature.Rule
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for updating a rule.</summary>
    type UpdateRuleRequest = { Pattern : string; TagId : Guid }

    [<Literal>]
    let Path = "/api/rules/{%O:guid}"

    let private update (queryContext : QueryContextFactory) (rule : Rule) (userId : string) =
        task {
            use! shared = queryContext.OpenContextAsync ()
            shared.BeginTransaction ()

            let row = RuleCodec.toRow rule userId

            let! _rowsAffected =
                updateTask shared {
                    for t in main.Rules do
                        entity row
                        excludeColumn t.Id
                        where (t.Id = rule.Id && t.UserId = userId)
                }

            let! result =
                selectTask shared {
                    for t in main.Rules do
                        where (t.Id = rule.Id && t.UserId = userId)
                        tryHead
                }

            shared.CommitTransaction ()

            let rule = result |> Option.map RuleCodec.fromRow

            return rule
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateRuleRequest) = Json.read ctx

                let! userId = Auth.getUserId ctx
                let! pattern = RulePattern.create req.Pattern

                let rule : Rule = {
                    Id = id
                    Pattern = pattern
                    TagId = req.TagId
                }

                let! updated = update queryContext rule userId

                match updated with
                | Some updated ->
                    log.Info ($"Updated rule %O{id}", LogProp.prop "ruleId" (id.ToString ()))
                    do! Json.write ctx (RuleResponse.fromDomain updated)
                | None ->
                    log.Warn ($"Rule %O{id} not found", LogProp.prop "ruleId" (id.ToString ()))
                    return! Error (NotFound $"Rule %O{id} not found")
            })

    let endpoint (queryContext : QueryContextFactory) =
        routef Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<UpdateRuleRequest>,
                responseBodies = [|
                    ResponseBody typeof<RuleResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Update a rule"
                        op.Description <- "Replaces the rule."
                        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
                        Task.CompletedTask
            )
        )
