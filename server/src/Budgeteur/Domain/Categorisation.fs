namespace Budgeteur.Domain.Categorisation

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

/// <summary>How a transaction is categorised: a tag and its source, the user's
/// decision that it has none, or a transfer. Kept apart from the transaction,
/// keyed by its id, so categorising changes without touching the
/// transaction's facts. An untagged transaction has no categorisation, so its
/// categorisation is <c>None</c>.</summary>
[<RequireQualifiedAccess>]
type Categorisation =
    /// <summary>The transaction has the tag.</summary>
    | Tagged of tagId : Guid * source : TagSource
    /// <summary>The user decided the transaction has no tag. Always manual: a
    /// rule never dismisses. See decision 1 in docs/quick-tagging.md.</summary>
    | Dismissed
    /// <summary>The transaction moves money between the user's own accounts,
    /// so it has no tag and is neither income nor expense. Set by the user or
    /// detected on import; rules never change it. See decision 1 in
    /// docs/quick-tagging.md.</summary>
    | Transfer

/// <summary>The transitions between untagged, tagged manually or by a rule,
/// dismissed, and transfer. Each takes the current categorisation last, so it
/// can be piped. See decision 4 in docs/auto-tagging.md.</summary>
module Categorisation =
    let private manual tagId =
        Categorisation.Tagged (tagId, TagSource.Manual)

    let private byRule tagId =
        Categorisation.Tagged (tagId, TagSource.Rule)

    /// <summary>Whether the categorisation makes the transaction a
    /// transfer.</summary>
    let isTransfer (categorisation : Categorisation option) : bool =
        categorisation = Some Categorisation.Transfer

    /// <summary>A transfer is neither income nor expense, so it has no tag.
    /// Fails when a request marks a transaction as a transfer and gives it a
    /// tag.</summary>
    let requireNoTagOnTransfer
        (isTransfer : bool)
        (tagId : Guid option)
        : Result<unit, DomainError> =
        match isTransfer, tagId with
        | true, Some _ ->
            Error (ValidationFailed "A transfer cannot have a tag")
        | _ -> Ok ()

    /// <summary>Creating a transaction as a transfer makes it a transfer; with
    /// a tag, manually tagged; otherwise, untagged.</summary>
    let onCreate
        (isTransfer : bool)
        (tagId : Guid option)
        : Categorisation option =
        match isTransfer with
        | true -> Some Categorisation.Transfer
        | false -> Option.map manual tagId

    /// <summary>Marking a transaction as a transfer makes it a transfer.
    /// Otherwise, updating to a different tag makes it manual and clearing the
    /// tag makes it untagged, including a transaction that was a transfer.
    /// Keeping the same tag keeps its source, so editing the amount of a
    /// rule-tagged transaction does not make it manual, and saving a dismissed
    /// transaction without a tag keeps it dismissed.</summary>
    let onUpdate
        (isTransfer : bool)
        (tagId : Guid option)
        (current : Categorisation option)
        : Categorisation option =
        match isTransfer, tagId, current with
        | true, _, _ -> Some Categorisation.Transfer
        | false, None, Some Categorisation.Dismissed -> current
        | false, None, _ -> None
        | false, Some tagId, Some (Categorisation.Tagged (currentTagId, _)) when
            currentTagId = tagId
            ->
            current
        | false, Some tagId, _ -> Some (manual tagId)

    /// <summary>Tag untagged: an untagged transaction gets the winning rule's
    /// tag, if any. A tagged, dismissed, or transfer transaction keeps its
    /// categorisation.</summary>
    let tagUntagged
        (winningTagId : Guid option)
        (current : Categorisation option)
        : Categorisation option =
        match current with
        | None -> Option.map byRule winningTagId
        | Some _ -> current

    /// <summary>Re-tag: a manual tag, a dismissal, or a transfer never
    /// changes. Otherwise the transaction gets the winning rule's tag, or
    /// becomes untagged when no rule wins.</summary>
    let retag
        (winningTagId : Guid option)
        (current : Categorisation option)
        : Categorisation option =
        match current with
        | Some (Categorisation.Tagged (_, TagSource.Manual))
        | Some Categorisation.Dismissed
        | Some Categorisation.Transfer -> current
        | Some (Categorisation.Tagged (_, TagSource.Rule))
        | None -> Option.map byRule winningTagId

    /// <summary>Quick tagging with a tag makes it manual, whatever the
    /// transaction had. See decision 1 in docs/quick-tagging.md.</summary>
    let onQuickTag (tagId : Guid) : Categorisation option = Some (manual tagId)

    /// <summary>Dismissing records that the transaction has no tag, whatever it
    /// had.</summary>
    let onDismiss : Categorisation option = Some Categorisation.Dismissed

    /// <summary>Marking a transaction as a transfer from quick tagging replaces
    /// whatever it had.</summary>
    let onTransfer : Categorisation option = Some Categorisation.Transfer
