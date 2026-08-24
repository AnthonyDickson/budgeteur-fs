namespace Budgeteur.Rule.Endpoints.Update

open System

/// <summary>Payload for updating a rule.</summary>
type UpdateRuleRequest = { Pattern : string; TagId : Guid }

module Update =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
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
    open Budgeteur.Rule

    [<Literal>]
    let Path = "/api/rules/{%O:guid}"

    let private update (queryContext : QueryContextFactory) (rule : Rule) (userId : string) =
        task {
            try
                use! shared = queryContext.OpenContextAsync ()
                shared.BeginTransaction ()

                let row = Rule.toRow rule userId

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

                let rule = result |> Option.map Rule.fromRow

                return Ok rule
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let private handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : UpdateRuleRequest) = Json.read ctx

                let! userId = Auth.getUserId ctx
                let! pattern = Validation.validateAndTrimPattern req.Pattern

                let rule = {
                    Id = id
                    Pattern = pattern
                    TagId = req.TagId
                }

                let! updated = update queryContext rule userId

                match updated with
                | Some updated ->
                    log.Info ($"Updated rule %O{id}", LogProp.prop "ruleId" (id.ToString ()))
                    do! Json.write ctx updated
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
                    ResponseBody typeof<Rule>
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
