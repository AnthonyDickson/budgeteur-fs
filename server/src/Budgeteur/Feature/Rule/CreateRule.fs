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

    /// <summary>Payload for creating a rule. The id is generated
    /// server-side.</summary>
    type CreateRuleRequest = { Pattern : string; TagId : Guid }

    [<Literal>]
    let Path = "/api/rules"

    /// <summary>Verify that the user has no rule with the same pattern under
    /// the comparison, whatever its tag. The database's <c>UNIQUE(UserId,
    /// Pattern COLLATE NOCASE)</c> folds ASCII case only, so the patterns are
    /// compared here. Used on create, where the rule does not exist yet, so no
    /// existing rule is excluded from the check.</summary>
    let private requirePatternIsUnique
        (queryContext : QueryContextFactory)
        (userId : string)
        (pattern : RulePattern)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for r in main.Rules do
                        where (r.UserId = userId)
                }

            let exists =
                rows
                |> Seq.exists (fun row ->
                    RulePattern.same (RuleCodec.fromRow row).Pattern pattern)

            return
                if exists then
                    Error (
                        ConstraintError
                            $"A rule with the pattern \
                            '{RulePattern.value pattern}' already exists"
                    )
                else
                    Ok ()
        }

    let private insert
        (queryContext : QueryContextFactory)
        (userId : string)
        (rule : Rule)
        =
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
                        Constraints.requireTagExists
                            queryContext
                            userId
                            req.TagId
                        requirePatternIsUnique queryContext userId pattern
                    ]

                let rule : Rule = {
                    Id = Guid.CreateVersion7 ()
                    Pattern = pattern
                    TagId = req.TagId
                }

                let! () = insert queryContext userId rule

                log.Info (
                    $"Created rule %O{rule.Id}",
                    LogProp.prop "ruleId" (rule.Id.ToString ())
                )

                ctx.SetStatusCode 201
                do! Json.write ctx (RuleResponse.fromDomain rule)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Create a rule"

        op.Description <- "Creates a new rule and returns it with status 201."

        op.Tags <- HashSet [ OpenApiTagReference "Rules" ]
        Task.CompletedTask

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
                configureOperation = configureOperation
            )
        )
