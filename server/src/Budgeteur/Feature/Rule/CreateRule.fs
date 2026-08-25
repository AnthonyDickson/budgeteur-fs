namespace Budgeteur.Feature.Rule

module CreateRule =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.Data.Sqlite
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

    /// <summary>Payload for creating a rule. The id is generated server-side.</summary>
    type CreateRuleRequest = { Pattern : string; TagId : Guid }

    [<Literal>]
    let Path = "/api/rules"

    let private insert (queryContext : QueryContextFactory) (rule : Rule) (userId : string) =
        task {
            let row = Rule.toRow rule userId

            try
                let! _ =
                    insertTask queryContext {
                        for t in main.Rules do
                            entity row
                    }

                return Ok ()
            with
            | :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
                return Error (Conflict $"A rule with ID %O{rule.Id} already exists")
            | ex -> return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : CreateRuleRequest) = Json.read ctx
                let! pattern = Validation.validateAndTrimPattern req.Pattern

                let rule = {
                    Id = Guid.CreateVersion7 ()
                    Pattern = pattern
                    TagId = req.TagId
                }

                let! () = insert queryContext rule userId

                log.Info ($"Created rule %O{rule.Id}", LogProp.prop "ruleId" (rule.Id.ToString ()))

                ctx.SetStatusCode 201
                do! Json.write ctx rule
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<CreateRuleRequest>,
                responseBodies = [|
                    ResponseBody (typeof<Rule>, statusCode = 201)
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
