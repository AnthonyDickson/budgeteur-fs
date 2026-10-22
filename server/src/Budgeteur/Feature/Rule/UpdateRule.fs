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
    open Budgeteur.Shared.OpenApi
    open Budgeteur.Shared.RequestLogging

    /// <summary>Payload for updating a rule.</summary>
    type UpdateRuleRequest = {
        Pattern : string

        /// <summary>What the rule proposes when it wins.</summary>
        [<SchemaHint.Enum(typeof<RuleTarget>)>]
        Target : string

        /// <summary>Required for a tag rule, and rejected for a transfer
        /// rule.</summary>
        TagId : Guid option
    }

    [<Literal>]
    let Path = "/api/rules/{%O:guid}"

    /// <summary>Verify that the user has no other rule with the same pattern
    /// under the comparison, whatever its target, excluding the rule being
    /// updated. The database's <c>UNIQUE(UserId, Pattern COLLATE NOCASE)</c>
    /// folds ASCII case only, so the patterns are compared here.</summary>
    let private requirePatternIsUnique
        (queryContext : QueryContextFactory)
        (userId : string)
        (rule : Rule)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for r in main.Rules do
                        where (r.Id <> rule.Id && r.UserId = userId)
                }

            let exists =
                rows
                |> Seq.exists (fun row ->
                    RulePattern.same
                        (RuleCodec.fromRow row).Pattern
                        rule.Pattern)

            return
                if exists then
                    Error (
                        ConstraintError
                            $"A rule with the pattern \
                            '{RulePattern.value rule.Pattern}' already exists"
                    )
                else
                    Ok ()
        }

    /// <summary>Replace the user's rule. Fails with <c>NotFound</c> when the
    /// user has no rule with the id.</summary>
    let private update
        (queryContext : QueryContextFactory)
        (userId : string)
        (rule : Rule)
        =
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

    let private handler
        (queryContext : QueryContextFactory)
        (id : Guid)
        : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateRuleRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx

                let! pattern = RulePattern.create req.Pattern
                let! target = RuleTarget.create req.Target req.TagId

                let rule : Rule = {
                    Id = id
                    Pattern = pattern
                    Target = target
                }

                do!
                    Constraints.requireAll [
                        Constraints.requireTagIfReferenced
                            queryContext
                            userId
                            (RuleTarget.tagId target)
                        requirePatternIsUnique queryContext userId rule
                    ]

                do! update queryContext userId rule

                log.Info (
                    $"Updated rule %O{id}",
                    LogProp.prop "ruleId" (id.ToString ())
                )

                do! Json.write ctx (RuleResponse.fromDomain rule)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Update a rule"
        op.Description <- "Replaces the rule."
        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
        Task.CompletedTask

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
                configureOperation = configureOperation
            )
        )
