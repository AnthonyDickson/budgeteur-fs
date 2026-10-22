namespace Budgeteur.Feature.QuickTag

open System

open Budgeteur.Domain.Rule
open Budgeteur.Domain.Tag
open Budgeteur.Domain.Transaction

/// <summary>The proposal for a queued transaction: the winning rule's target,
/// and the rule's pattern so the user can check why. Computed when the queue is
/// read, never stored. See decision 6 in docs/transfer-rules.md.</summary>
type Suggestion = {
    Target : RuleTarget
    Pattern : RulePattern
}

/// <summary>A queued transaction and its suggestion, if any.</summary>
type Suggested<'Transaction> = {
    Transaction : 'Transaction
    Suggestion : Suggestion option
}

/// <summary>A batch of the queue, as the queue read returns it.</summary>
type QueueBatch<'Transaction> = {
    /// <summary>The first batch of the queue, or of the queued transactions
    /// suggested the filter's target.</summary>
    Batch : Suggested<'Transaction> list
    /// <summary>How many transactions the queue holds, or how many are
    /// suggested the filter's target.</summary>
    Total : int
    /// <summary>How many queued transactions are suggested each target, over
    /// the whole queue, in the order of the row buttons.</summary>
    Counts : (RuleTarget * int) list
}

module Suggestion =
    /// <summary>The suggestion for each description: the winning rule's
    /// target and pattern, whatever the target. Apply it to the rules once and
    /// reuse the result for many descriptions.</summary>
    let suggester
        (rules : Rule list)
        : TransactionDescription -> Suggestion option =
        let winner = Rule.winner rules

        fun description ->
            winner description
            |> Option.map (fun rule -> {
                Target = rule.Target
                Pattern = rule.Pattern
            })

    /// <summary>Where a target's count sits, as the row buttons are ordered:
    /// expense tags, then income tags, each by name, then transfer. See
    /// decision 5 in docs/quick-tagging.md.</summary>
    let private buttonOrder (tags : Tag list) : RuleTarget -> int * string =
        let byId = tags |> List.map (fun tag -> tag.Id, tag) |> Map.ofList

        fun target ->
            match target with
            | RuleTarget.Tag tagId ->
                match Map.tryFind tagId byId with
                | Some tag ->
                    let kind =
                        match tag.Kind with
                        | Expense -> 0
                        | Income -> 1

                    kind, TagName.value tag.Name
                // A rule's tag is the user's, so in practice every tag is
                // found.
                | None -> 2, string tagId
            | RuleTarget.Transfer -> 3, ""

    /// <summary>Read a batch of the queue: suggest every queued transaction,
    /// count the suggestions over the whole queue, and keep the transactions
    /// suggested the filter's target, if any. <c>queue</c> is newest first.
    /// Suggestions are computed in memory, so the filter and its total are
    /// too. See decision 7 in docs/transfer-rules.md.</summary>
    let readQueue
        (batchSize : int)
        (rules : Rule list)
        (tags : Tag list)
        (describe : 'Transaction -> TransactionDescription)
        (filter : RuleTarget option)
        (queue : 'Transaction list)
        : QueueBatch<'Transaction> =
        let suggest = suggester rules

        let suggested =
            queue
            |> List.map (fun transaction -> {
                Transaction = transaction
                Suggestion = suggest (describe transaction)
            })

        let counts =
            suggested
            |> List.choose (fun row -> row.Suggestion |> Option.map _.Target)
            |> List.countBy id
            |> List.sortBy (fst >> buttonOrder tags)

        let kept =
            match filter with
            | Some target ->
                suggested
                |> List.filter (fun row ->
                    row.Suggestion
                    |> Option.exists (fun s -> s.Target = target))
            | None -> suggested

        {
            Batch = List.truncate batchSize kept
            Total = List.length kept
            Counts = counts
        }
