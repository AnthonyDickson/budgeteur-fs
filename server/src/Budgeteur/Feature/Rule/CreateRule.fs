namespace Budgeteur.Feature.Rule

module CreateRule =
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
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for creating a rule. The id is generated server-side.</summary>
    type CreateRuleRequest = { Pattern : string; TagId : Guid }

    [<Literal>]
    let Path = "/api/rules"

    /// <summary>Verify that no rule with the same pattern and tag already exists for this user
    /// (the <c>UNIQUE(UserId, Pattern, TagId)</c> constraint). Used on create, where the rule
    /// does not exist yet, so no existing rule is excluded from the check.</summary>
    let private requireRuleIsUnique
        (queryContext : QueryContextFactory)
        (userId : string)
        (pattern : RulePattern)
        (tagId : Guid)
        =
        task {
            let pattern = RulePattern.value pattern

            let! rowCount =
                selectTask queryContext {
                    for r in main.Rules do
                        where (r.Pattern = pattern && r.TagId = tagId && r.UserId = userId)
                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (ConstraintError $"The rule pattern '{pattern}' for tag {tagId} already exists")
        }

    let private insert (queryContext : QueryContextFactory) (userId : string) (rule : Rule) =
        task {
            let row = RuleCodec.toRow rule userId

            let! _ =
                insertTask queryContext {
                    for t in main.Rules do
                        entity row
                }

            return ()
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateRuleRequest) = Json.read ctx

                let! pattern = RulePattern.create req.Pattern

                do!
                    Constraints.requireAll [
                        Constraints.requireTagExists queryContext userId req.TagId
                        requireRuleIsUnique queryContext userId pattern req.TagId
                    ]

                let rule : Rule = {
                    Id = Guid.CreateVersion7 ()
                    Pattern = pattern
                    TagId = req.TagId
                }

                let! () = insert queryContext userId rule

                log.Info ($"Created rule %O{rule.Id}", LogProp.prop "ruleId" (rule.Id.ToString ()))

                ctx.SetStatusCode 201
                do! Json.write ctx (RuleResponse.fromDomain rule)
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateRuleRequest>,
                responseBodies = [|
                    ResponseBody (typeof<RuleResponse>, statusCode = 201)
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "Create a rule"
                        op.Description <- "Creates a new rule and returns it with status 201."
                        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
                        Task.CompletedTask
            )
        )
