namespace Budgeteur.Feature.AutoTag

open System

open Budgeteur.Domain.Rule
open Budgeteur.Domain.TagAssignment
open Budgeteur.Domain.Transaction

/// <summary>Which transactions an auto-tagging run recomputes. See decision 5
/// in docs/auto-tagging.md.</summary>
type AutoTagAction =
    /// <summary>Apply rules to untagged transactions only.</summary>
    | TagUntagged
    /// <summary>Recompute every transaction without a manual tag.</summary>
    | Retag

module AutoTagAction =
    let parse string =
        match string with
        | "TagUntagged" -> Ok TagUntagged
        | "Retag" -> Ok Retag
        | other ->
            Error
                $"\"{other}\" is not a valid value for AutoTagAction, \
                expecting one of \"TagUntagged\" or \"Retag\"."

/// <summary>A transaction a run may tag: its description and current
/// assignment.</summary>
type Candidate = {
    TransactionId : Guid
    Description : TransactionDescription
    Assignment : TagAssignment option
}

/// <summary>A change to one transaction's assignment. Transactions a run
/// leaves as they are have no change.</summary>
type Change =
    /// <summary>An untagged transaction got a rule tag.</summary>
    | Tagged of transactionId : Guid * assignment : TagAssignment
    /// <summary>A rule tag changed to another rule's tag.</summary>
    | Changed of transactionId : Guid * assignment : TagAssignment
    /// <summary>A rule tag no rule wins any more was removed.</summary>
    | Cleared of transactionId : Guid

/// <summary>How many transactions a run tagged, changed, and cleared.</summary>
type Counts = {
    Tagged : int
    Changed : int
    Cleared : int
}

/// <summary>What a pattern matches among a user's transactions. See decision
/// 7 in docs/auto-tagging.md.</summary>
type Matches = {
    /// <summary>How many transactions the pattern matches.</summary>
    Count : int
    /// <summary>How many transactions there are to match.</summary>
    Total : int
    /// <summary>Distinct descriptions from the most recent matches, most recent
    /// first, so a recurring merchant does not fill the samples with
    /// copies.</summary>
    Samples : TransactionDescription list
}

module AutoTag =
    [<Literal>]
    let MaxSamples = 5

    /// <summary>The assignment changes a run makes: each candidate goes through
    /// the action's transition with the winning rule's tag, and only the
    /// candidates whose assignment differs are returned.</summary>
    let changes
        (action : AutoTagAction)
        (rules : Rule list)
        (candidates : Candidate list)
        : Change list =
        let winner = Rule.winner rules

        let transition =
            match action with
            | TagUntagged -> TagAssignment.tagUntagged
            | Retag -> TagAssignment.retag

        candidates
        |> List.choose (fun candidate ->
            let winningTagId =
                winner candidate.Description |> Option.map _.TagId

            let before = candidate.Assignment
            let after = transition winningTagId before

            match before, after with
            | _ when before = after -> None
            | None, Some after ->
                Some (Tagged (candidate.TransactionId, after))
            | Some _, Some after ->
                Some (Changed (candidate.TransactionId, after))
            | Some _, None -> Some (Cleared candidate.TransactionId)
            | None, None -> None)

    /// <summary>How many of each kind of change a run made.</summary>
    let counts (changes : Change list) : Counts =
        let add counts change =
            match change with
            | Tagged _ -> {
                counts with
                    Tagged = counts.Tagged + 1
              }
            | Changed _ -> {
                counts with
                    Changed = counts.Changed + 1
              }
            | Cleared _ -> {
                counts with
                    Cleared = counts.Cleared + 1
              }

        List.fold add { Tagged = 0; Changed = 0; Cleared = 0 } changes

    /// <summary>What the pattern matches among the descriptions, which are
    /// ordered most recent first. Counts matches, not wins: whether the rule
    /// would win depends on the other rules.</summary>
    let matches
        (pattern : RulePattern)
        (descriptions : TransactionDescription list)
        : Matches =
        let matching =
            descriptions
            |> List.filter (fun description ->
                RulePattern.matches description pattern)

        {
            Count = List.length matching
            Total = List.length descriptions
            Samples = matching |> List.distinct |> List.truncate MaxSamples
        }
