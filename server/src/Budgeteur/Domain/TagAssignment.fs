namespace Budgeteur.Domain.TagAssignment

open System

/// <summary>Where a transaction's tag came from. Rules never change a manual
/// tag; a rule tag is derived data that re-tagging recomputes.</summary>
[<RequireQualifiedAccess>]
type TagSource =
    /// <summary>The user set the tag.</summary>
    | Manual
    /// <summary>Auto-tagging set the tag.</summary>
    | Rule

module TagSource =
    let toString source =
        match source with
        | TagSource.Manual -> "Manual"
        | TagSource.Rule -> "Rule"

    let parse string =
        match string with
        | "Manual" -> Ok TagSource.Manual
        | "Rule" -> Ok TagSource.Rule
        | other ->
            Error
                $"\"{other}\" is not a valid value for TagSource, expecting \
                one of \"Manual\" or \"Rule\"."

/// <summary>A transaction's tag and its source. Kept apart from the
/// transaction, keyed by its id, so tagging changes without touching the
/// transaction's facts. An untagged transaction has no assignment, so its
/// assignment is <c>None</c>.</summary>
type TagAssignment = { TagId : Guid; Source : TagSource }

/// <summary>The transitions between untagged, manually tagged, and tagged by a
/// rule. Each takes the current assignment last, so it can be piped. See
/// decision 4 in docs/auto-tagging.md.</summary>
module TagAssignment =
    let private manual tagId = {
        TagId = tagId
        Source = TagSource.Manual
    }

    let private byRule tagId = {
        TagId = tagId
        Source = TagSource.Rule
    }

    /// <summary>Creating a transaction with a tag makes it manual; without
    /// one, untagged.</summary>
    let onCreate (tagId : Guid option) : TagAssignment option =
        Option.map manual tagId

    /// <summary>Updating a transaction to a different tag makes it manual and
    /// clearing the tag makes it untagged. Keeping the same tag keeps its
    /// source, so editing the amount of a rule-tagged transaction does not
    /// make it manual.</summary>
    let onUpdate
        (tagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match tagId, current with
        | None, _ -> None
        | Some tagId, Some current when current.TagId = tagId -> Some current
        | Some tagId, _ -> Some (manual tagId)

    /// <summary>Tag untagged: an untagged transaction gets the winning rule's
    /// tag, if any. A tagged transaction keeps its tag, whatever its
    /// source.</summary>
    let tagUntagged
        (winningTagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match current with
        | None -> Option.map byRule winningTagId
        | Some _ -> current

    /// <summary>Re-tag: a manual tag never changes. Otherwise the transaction
    /// gets the winning rule's tag, or becomes untagged when no rule
    /// wins.</summary>
    let retag
        (winningTagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match current with
        | Some { Source = TagSource.Manual } -> current
        | Some { Source = TagSource.Rule }
        | None -> Option.map byRule winningTagId
