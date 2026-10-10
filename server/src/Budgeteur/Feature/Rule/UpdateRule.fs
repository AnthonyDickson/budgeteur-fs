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

    open Budgeteur.Data
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

    /// <summary>Verify that no other rule with the same pattern and tag exists for this user,
    /// excluding the rule being updated (the <c>UNIQUE(UserId, Pattern, TagId)</c> constraint).</summary>
    let private requireRuleIsUnique (queryContext : QueryContextFactory) (userId : string) (rule : Rule) =
        task {
            let pattern = RulePattern.value rule.Pattern

            let! rowCount =
                selectTask queryContext {
                    for r in main.Rules do
                        where (
                            r.Id <> rule.Id
                            && r.Pattern = pattern
                            && r.TagId = rule.TagId
                            && r.UserId = userId
                        )

                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError $"The rule pattern '{pattern}' for tag {rule.TagId} already exists")
        }

    /// <summary>Replace the user's rule. Fails with <c>NotFound</c> when the user has no rule with
    /// the id.</summary>
    let private update (queryContext : QueryContextFactory) (userId : string) (rule : Rule) =
        task {
            let row = RuleCodec.toRow rule userId

            let! rowsAffected =
                updateTask queryContext {
                    for t in main.Rules do
                        entity row
                        excludeColumn t.Id
                        where (t.Id = rule.Id && t.UserId = userId)
                }

            if rowsAffected = 0 then
                return Error (NotFound $"Rule %O{rule.Id} not found")
            else
                return Ok ()
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

                do!
                    Constraints.requireAll [
                        Constraints.requireTagExists queryContext userId req.TagId
                        requireRuleIsUnique queryContext userId rule
                    ]

                do! update queryContext userId rule

                log.Info ($"Updated rule %O{id}", LogProp.prop "ruleId" (id.ToString ()))
                do! Json.write ctx (RuleResponse.fromDomain rule)
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
