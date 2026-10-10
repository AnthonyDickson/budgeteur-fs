namespace Budgeteur.Feature.AutoTag

open Budgeteur.Shared.OpenApi

/// <summary>Payload for an auto-tagging run.</summary>
type RunAutoTagRequest = {
    /// <summary>TagUntagged applies rules to untagged transactions only. Retag
    /// recomputes every transaction without a manual tag, so rule tags may
    /// change or be cleared.</summary>
    [<SchemaHint.Enum(typeof<AutoTagAction>)>]
    Action : string
}

/// <summary>How many transactions a run changed.</summary>
type RunAutoTagResponse = {
    /// <summary>Untagged transactions that got a rule tag.</summary>
    Tagged : int

    /// <summary>Rule tags changed to another rule's tag.</summary>
    Changed : int

    /// <summary>Rule tags removed because no rule matches any more.</summary>
    Cleared : int
}

module RunAutoTag =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/auto-tag"

    let private loadRules (queryContext : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for r in main.Rules do
                        where (r.UserId = userId)
                }

            return rows |> Seq.map RuleCodec.fromRow |> List.ofSeq
        }

    /// <summary>Every transaction of the user, with its description and
    /// assignment. Transfers are included: rules apply to them too.</summary>
    let private loadCandidates (queryContext : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.TagAssignments
                                          on
                                          (t.Id = a.TransactionId)

                        where (t.UserId = userId)
                        select (t.Id, t.Description, a)
                }

            return
                rows
                |> Seq.map (fun (id, description, assignment) -> {
                    TransactionId = id
                    Description =
                        TransactionDescription.unsafeFromString description
                    Assignment =
                        assignment.ToOption ()
                        |> Option.map TagAssignmentCodec.fromRow
                })
                |> List.ofSeq
        }

    let private write
        (queryContext : QueryContext)
        (userId : string)
        (changes : Change list)
        =
        task {
            for change in changes do
                match change with
                | Tagged (id, assignment)
                | Changed (id, assignment) ->
                    do!
                        TagAssignmentStore.save
                            queryContext
                            userId
                            id
                            (Some assignment)
                | Cleared id ->
                    do! TagAssignmentStore.save queryContext userId id None
        }

    /// <summary>Load the user's rules and candidates, and write the changes,
    /// in one database transaction. Microsoft.Data.Sqlite begins it with
    /// <c>BEGIN IMMEDIATE</c>, so no other write lands between the load and the
    /// write, and a manual tag set meanwhile cannot be overwritten.</summary>
    let private run
        (queryContext : QueryContextFactory)
        (userId : string)
        (action : AutoTagAction)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()
            let! rules = loadRules ctx userId
            let! candidates = loadCandidates ctx userId
            let changes = AutoTag.changes action rules candidates
            do! write ctx userId changes
            ctx.CommitTransaction ()
            return AutoTag.counts changes
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : RunAutoTagRequest) = Json.read ctx

                let! action =
                    AutoTagAction.parse req.Action
                    |> Result.mapError ValidationFailed

                let! counts = run queryContext userId action

                log.Info (
                    $"Auto-tagged with %s{req.Action}: %i{counts.Tagged} \
                    tagged, %i{counts.Changed} changed, %i{counts.Cleared} \
                    cleared",
                    LogProp.prop "tagged" counts.Tagged,
                    LogProp.prop "changed" counts.Changed,
                    LogProp.prop "cleared" counts.Cleared
                )

                do!
                    Json.write ctx {
                        RunAutoTagResponse.Tagged = counts.Tagged
                        Changed = counts.Changed
                        Cleared = counts.Cleared
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Run auto-tagging"

        op.Description <-
            "Applies the user's rules to their transactions and returns how \
            many were tagged, changed, and cleared. Manual tags never change."

        op.Tags <- HashSet [ OpenApiTagReference "Auto-tagging" ]
        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<RunAutoTagRequest>,
                responseBodies = [|
                    ResponseBody typeof<RunAutoTagResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
