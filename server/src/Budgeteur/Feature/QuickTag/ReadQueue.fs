namespace Budgeteur.Feature.QuickTag

open System

open Budgeteur.Domain.Rule
open Budgeteur.Shared.OpenApi

/// <summary>What a rule suggests for a queued transaction.</summary>
type SuggestionResponse = {
    /// <summary>The suggested categorisation: a tag, or a transfer.</summary>
    [<SchemaHint.Enum(typeof<RuleTarget>)>]
    Target : string

    /// <summary>The suggested tag. Absent for a transfer.</summary>
    TagId : Guid option

    /// <summary>The pattern of the rule that suggests it.</summary>
    Pattern : string
}

/// <summary>A transaction waiting for a tag.</summary>
type QueuedTransactionResponse = {
    Id : Guid

    /// <summary>A debit (negative) or credit (positive). Serialised as a
    /// string.</summary>
    Amount : decimal

    Description : string

    /// <summary>The calendar date the transaction occurred.</summary>
    Date : DateOnly

    /// <summary>The name of the transaction's account, if it has one.</summary>
    AccountName : string option

    /// <summary>The winning rule's suggestion from the user's current rules,
    /// or none when no rule matches.</summary>
    Suggestion : SuggestionResponse option
}

/// <summary>How many queued transactions are suggested a
/// categorisation.</summary>
type SuggestionCountResponse = {
    /// <summary>The suggested categorisation: a tag, or a transfer.</summary>
    [<SchemaHint.Enum(typeof<RuleTarget>)>]
    Target : string

    /// <summary>The suggested tag. Absent for a transfer.</summary>
    TagId : Guid option

    Count : int
}

/// <summary>A batch of the quick tagging queue.</summary>
type QueueResponse = {
    /// <summary>Up to 50 of the user's untagged transactions, newest first,
    /// only those suggested the filter's categorisation when one is given.
    /// Tagging, dismissing, or marking them as transfers removes them from the
    /// queue, so fetching again returns the next batch.</summary>
    Transactions : QueuedTransactionResponse list

    /// <summary>How many transactions the whole queue holds, or how many are
    /// suggested the filter's categorisation.</summary>
    Total : int

    /// <summary>How many queued transactions are suggested each
    /// categorisation, over the whole queue whatever the filter: expense tags,
    /// then income tags, each by name, then transfer.</summary>
    Suggestions : SuggestionCountResponse list
}

module ReadQueue =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.AspNetCore.Http
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/quick-tag"

    [<Literal>]
    let BatchSize = 50

    /// <summary>The user's whole queue: transactions without a
    /// categorisation, which excludes dismissed ones and transfers, newest
    /// first, with their account names. Every queued transaction is suggested
    /// and counted, not only the batch. See decision 2 in
    /// docs/quick-tagging.md.</summary>
    let private readQueued
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.UserId = userId && isNullValue a.TransactionId)

                        orderByDescending t.Date
                        thenByDescending t.Id
                        select (t, account.Name)
                }

            return
                rows
                |> Seq.map (fun (row, accountName) ->
                    TransactionCodec.fromRow row, accountName)
                |> List.ofSeq
        }

    let private readRules
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for r in main.Rules do
                        where (r.UserId = userId)
                }

            return rows |> Seq.map RuleCodec.fromRow |> List.ofSeq
        }

    let private readTags
        (queryContext : QueryContextFactory)
        (userId : string)
        =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.UserId = userId)
                }

            return rows |> Seq.map TagCodec.fromRow |> List.ofSeq
        }

    let private queryParam (ctx : HttpContext) (name : string) =
        match ctx.Request.Query.TryGetValue name with
        | true, values when not (String.IsNullOrWhiteSpace (string values)) ->
            Some (string values)
        | _ -> None

    /// <summary>The optional filter: a target and, for a tag, its id,
    /// validated as for rules.</summary>
    let private parseFilter (ctx : HttpContext) =
        match queryParam ctx "target", queryParam ctx "tagId" with
        | None, None -> Ok None
        | None, Some _ ->
            Error (
                ValidationFailed "The query parameter 'tagId' needs a 'target'"
            )
        | Some target, tagId ->
            result {
                let! tagId =
                    match tagId with
                    | None -> Ok None
                    | Some tagId ->
                        match Guid.TryParse tagId with
                        | true, tagId -> Ok (Some tagId)
                        | false, _ ->
                            Error (
                                ValidationFailed
                                    $"The query parameter 'tagId' must be a \
                                    GUID, got '{tagId}'"
                            )

                let! target = RuleTarget.create target tagId
                return Some target
            }

    let private suggestionResponse (suggestion : Suggestion) = {
        Target = RuleTarget.kind suggestion.Target
        TagId = RuleTarget.tagId suggestion.Target
        Pattern = RulePattern.value suggestion.Pattern
    }

    let private transactionResponse
        (row : Suggested<Transaction * string option>)
        : QueuedTransactionResponse =
        let transaction, accountName = row.Transaction

        {
            Id = transaction.Id
            Amount = Money.value transaction.Amount
            Description = TransactionDescription.value transaction.Description
            Date = transaction.Date
            AccountName = accountName
            Suggestion = Option.map suggestionResponse row.Suggestion
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! filter = parseFilter ctx

                let! queued, rules, tags =
                    task {
                        let! queued = readQueued queryContext userId
                        and! rules = readRules queryContext userId
                        and! tags = readTags queryContext userId
                        return queued, rules, tags
                    }

                let read =
                    Suggestion.readQueue
                        BatchSize
                        rules
                        tags
                        (fun (transaction : Transaction, _) ->
                            transaction.Description)
                        filter
                        queued

                log.Info (
                    $"Returned %i{List.length read.Batch} of %i{read.Total} \
                    queued transactions",
                    LogProp.prop "total" read.Total
                )

                do!
                    Json.write ctx {
                        Transactions = List.map transactionResponse read.Batch
                        Total = read.Total
                        Suggestions =
                            read.Counts
                            |> List.map (fun (target, count) -> {
                                SuggestionCountResponse.Target =
                                    RuleTarget.kind target
                                TagId = RuleTarget.tagId target
                                Count = count
                            })
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Read the quick tagging queue"

        op.Description <-
            "Returns the first batch of the user's untagged transactions, \
            newest first, each with the suggestion of the winning rule, and \
            how many the queue holds. Also returns how many queued \
            transactions are suggested each categorisation, over the whole \
            queue. With a target, returns only the transactions suggested \
            it, and their total. \
            Transfers have a categorisation, so they are not in the queue."

        let parameter name description =
            OpenApiParameter (
                Name = name,
                In = Nullable ParameterLocation.Query,
                Required = false,
                Description = description,
                Schema = OpenApiSchema (Type = Nullable JsonSchemaType.String)
            )
            :> IOpenApiParameter

        op.Parameters <-
            ResizeArray [
                parameter
                    "target"
                    "Only transactions suggested this categorisation: Tag or \
                    Transfer."
                parameter
                    "tagId"
                    "The suggested tag, required with the Tag target and \
                    rejected with Transfer."
            ]

        op.Tags <- HashSet [ OpenApiTagReference "Quick tagging" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<QueueResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
