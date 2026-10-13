namespace Budgeteur.Domain.TagAssignment

open System

open Budgeteur.Shared.DomainError

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

/// <summary>A transaction's tag and its source, or the user's decision that it
/// has none. Kept apart from the transaction, keyed by its id, so tagging
/// changes without touching the transaction's facts. An untagged transaction
/// has no assignment, so its assignment is <c>None</c>.</summary>
[<RequireQualifiedAccess>]
type TagAssignment =
    /// <summary>The transaction has the tag.</summary>
    | Tagged of tagId : Guid * source : TagSource
    /// <summary>The user decided the transaction has no tag. Always manual: a
    /// rule never dismisses. See decision 1 in docs/quick-tagging.md.</summary>
    | Dismissed

/// <summary>The transitions between untagged, tagged manually or by a rule,
/// and dismissed. Each takes the current assignment last, so it can be piped.
/// See decision 4 in docs/auto-tagging.md.</summary>
module TagAssignment =
    let private manual tagId =
        TagAssignment.Tagged (tagId, TagSource.Manual)

    let private byRule tagId =
        TagAssignment.Tagged (tagId, TagSource.Rule)

    /// <summary>A transfer moves money between the user's own accounts, so it
    /// is neither income nor expense and has no tag. Fails when a transfer is
    /// given one.</summary>
    let requireNoTagOnTransfer
        (isTransfer : bool)
        (tagId : Guid option)
        : Result<unit, DomainError> =
        match isTransfer, tagId with
        | true, Some _ ->
            Error (ValidationFailed "A transfer cannot have a tag")
        | _ -> Ok ()

    /// <summary>Creating a transaction with a tag makes it manual; without
    /// one, untagged.</summary>
    let onCreate (tagId : Guid option) : TagAssignment option =
        Option.map manual tagId

    /// <summary>Updating a transaction to a different tag makes it manual and
    /// clearing the tag makes it untagged. Keeping the same tag keeps its
    /// source, so editing the amount of a rule-tagged transaction does not
    /// make it manual, and saving a dismissed transaction without a tag keeps
    /// it dismissed. A transfer has no assignment, so marking a transaction as
    /// a transfer removes any it had.</summary>
    let onUpdate
        (isTransfer : bool)
        (tagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match isTransfer, tagId, current with
        | true, _, _ -> None
        | false, None, Some TagAssignment.Dismissed -> current
        | false, None, _ -> None
        | false, Some tagId, Some (TagAssignment.Tagged (currentTagId, _)) when
            currentTagId = tagId
            ->
            current
        | false, Some tagId, _ -> Some (manual tagId)

    /// <summary>Tag untagged: an untagged transaction gets the winning rule's
    /// tag, if any. A tagged or dismissed transaction keeps its
    /// assignment.</summary>
    let tagUntagged
        (winningTagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match current with
        | None -> Option.map byRule winningTagId
        | Some _ -> current

    /// <summary>Re-tag: a manual tag or a dismissal never changes. Otherwise
    /// the transaction gets the winning rule's tag, or becomes untagged when
    /// no rule wins.</summary>
    let retag
        (winningTagId : Guid option)
        (current : TagAssignment option)
        : TagAssignment option =
        match current with
        | Some (TagAssignment.Tagged (_, TagSource.Manual))
        | Some TagAssignment.Dismissed -> current
        | Some (TagAssignment.Tagged (_, TagSource.Rule))
        | None -> Option.map byRule winningTagId

    /// <summary>Quick tagging with a tag makes it manual, whatever the
    /// transaction had. See decision 1 in docs/quick-tagging.md.</summary>
    let onQuickTag (tagId : Guid) : TagAssignment option = Some (manual tagId)

    /// <summary>Dismissing records that the transaction has no tag, whatever it
    /// had.</summary>
    let onDismiss : TagAssignment option = Some TagAssignment.Dismissed
