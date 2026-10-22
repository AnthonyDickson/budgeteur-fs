namespace Budgeteur.Feature.QuickTag

open System

open Budgeteur.Domain.Rule
open Budgeteur.Shared.OpenApi

/// <summary>Payload for approving a suggestion for the queued transactions
/// shown.</summary>
type ApprovalRequest = {
    /// <summary>The categorisation to apply: a tag, or a transfer.</summary>
    [<SchemaHint.Enum(typeof<RuleTarget>)>]
    Target : string

    /// <summary>Required for the Tag target, and rejected for
    /// Transfer.</summary>
    TagId : Guid option

    /// <summary>The transactions to approve it for: at most a batch of the
    /// queue.</summary>
    TransactionIds : Guid list
}

/// <summary>What an approval changed.</summary>
type ApprovalResponse = {
    /// <summary>How many of the transactions were still in the queue and got
    /// the categorisation.</summary>
    Changed : int
}

module ApproveSuggestion =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/quick-tag/approvals"

    /// <summary>Apply the categorisation to the listed transactions still in
    /// the queue, in one database transaction, and return how many changed.
    /// Every id must be the user's transaction, checked before the write, so
    /// one deleted since the page was read fails the whole request. One
    /// categorised meanwhile, in another tab, is not in the queue, so it is
    /// skipped rather than overwritten.</summary>
    let private approve
        (queryContext : QueryContextFactory)
        (userId : string)
        (target : RuleTarget)
        (transactionIds : Guid list)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let ids = List.distinct transactionIds

            let! rows =
                selectTask ctx {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        where (t.UserId = userId && t.Id |=| ids)
                        select (t.Id, a.TransactionId)
                }

            let found = rows |> Seq.map fst |> Set.ofSeq

            match ids |> List.tryFind (found.Contains >> not) with
            | Some missing ->
                return Error (NotFound $"Transaction %O{missing} not found")
            | None ->
                let queued =
                    rows
                    |> Seq.filter (fun (_, categorised) -> categorised.IsNone)
                    |> Seq.map fst
                    |> List.ofSeq

                for id in queued do
                    do!
                        CategorisationStore.save
                            ctx
                            userId
                            id
                            (Categorisation.onApprove target)

                ctx.CommitTransaction ()
                return Ok (List.length queued)
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! (req : ApprovalRequest) = Json.read ctx
                let! userId = Auth.getUserId ctx
                let! target = RuleTarget.create req.Target req.TagId

                do!
                    List.length req.TransactionIds <= ReadQueue.BatchSize
                    |> Result.requireTrue (
                        ValidationFailed
                            $"An approval can list at most \
                            %i{ReadQueue.BatchSize} transactions"
                    )

                do!
                    Constraints.requireOne (
                        Constraints.requireTagIfReferenced
                            queryContext
                            userId
                            (RuleTarget.tagId target)
                    )

                let! changed =
                    approve queryContext userId target req.TransactionIds

                log.Info (
                    $"Approved %s{req.Target} for %i{changed} transactions",
                    LogProp.prop "changed" changed
                )

                do! Json.write ctx { Changed = changed }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Approve a suggestion"

        op.Description <-
            "Gives the listed transactions that are still in the quick \
            tagging queue the tag or transfer, with the Accepted source, in \
            one database transaction, and returns how many changed. \
            Transactions categorised since the queue was read are skipped. \
            Lists more than a batch of 50, or a tag the user does not have, \
            are 400; any transaction the user does not have is 404, and \
            nothing is written."

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<ApprovalRequest>,
                responseBodies = [|
                    ResponseBody typeof<ApprovalResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
