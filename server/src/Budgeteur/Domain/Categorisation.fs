namespace Budgeteur.Domain.Categorisation

open System

open Budgeteur.Domain.Rule
open Budgeteur.Shared.DomainError

/// <summary>Who decided a categorisation, whatever its kind. Re-tag recomputes
/// only rule categorisations; every other source is a decision re-tag never
/// changes. See decision 4 in docs/transfer-rules.md.</summary>
[<RequireQualifiedAccess>]
type Source =
    /// <summary>The user decided, without choosing a suggestion.</summary>
    | Manual
    /// <summary>The user chose the suggestion, on one row or by approving
    /// it.</summary>
    | Accepted
    /// <summary>Auto-tagging applied a rule's proposal.</summary>
    | Rule
    /// <summary>Import detected a transfer by the other party's account
    /// number.</summary>
    | Detected

module Source =
    let toString source =
        match source with
        | Source.Manual -> "Manual"
        | Source.Accepted -> "Accepted"
        | Source.Rule -> "Rule"
        | Source.Detected -> "Detected"

    let parse string =
        match string with
        | "Manual" -> Ok Source.Manual
        | "Accepted" -> Ok Source.Accepted
        | "Rule" -> Ok Source.Rule
        | "Detected" -> Ok Source.Detected
        | other ->
            Error
                $"\"{other}\" is not a valid value for Source, expecting one \
                of \"Manual\", \"Accepted\", \"Rule\", or \"Detected\"."

/// <summary>How a transaction is categorised: a tag or a transfer with its
/// source, or the user's decision that it has none. Kept apart from the
/// transaction, keyed by its id, so categorising changes without touching the
/// transaction's facts. An untagged transaction has no categorisation, so its
/// categorisation is <c>None</c>.</summary>
[<RequireQualifiedAccess>]
type Categorisation =
    /// <summary>The transaction has the tag.</summary>
    | Tagged of tagId : Guid * source : Source
    /// <summary>The user decided the transaction has no tag. Always the user's
    /// decision, so it has no source: no proposal ever dismisses. See decision
    /// 1 in docs/quick-tagging.md.</summary>
    | Dismissed
    /// <summary>The transaction moves money between the user's own accounts,
    /// so it has no tag and is neither income nor expense. See decision 1 in
    /// docs/quick-tagging.md.</summary>
    | Transfer of source : Source

/// <summary>The transitions between untagged, tagged, dismissed, and transfer.
/// Each takes the current categorisation last, so it can be piped. See
/// decision 4 in docs/auto-tagging.md.</summary>
module Categorisation =
    let private manual tagId =
        Categorisation.Tagged (tagId, Source.Manual)

    /// <summary>Who decided the categorisation. A dismissal is always the
    /// user's decision.</summary>
    let source (categorisation : Categorisation) : Source =
        match categorisation with
        | Categorisation.Tagged (_, source)
        | Categorisation.Transfer source -> source
        | Categorisation.Dismissed -> Source.Manual

    /// <summary>Whether the categorisation makes the transaction a
    /// transfer.</summary>
    let isTransfer (categorisation : Categorisation option) : bool =
        match categorisation with
        | Some (Categorisation.Transfer _) -> true
        | Some (Categorisation.Tagged _)
        | Some Categorisation.Dismissed
        | None -> false

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

    /// <summary>Creating a transaction as a transfer makes it a manual
    /// transfer; with a tag, manually tagged; otherwise, untagged.</summary>
    let onCreate
        (isTransfer : bool)
        (tagId : Guid option)
        : Categorisation option =
        match isTransfer with
        | true -> Some (Categorisation.Transfer Source.Manual)
        | false -> Option.map manual tagId

    /// <summary>Marking a transaction as a transfer makes it a manual
    /// transfer, and keeping it a transfer keeps its source, so saving a
    /// detected transfer keeps it detected. Otherwise, updating to a different
    /// tag makes it manual and clearing the tag makes it untagged, including a
    /// transaction that was a transfer. Keeping the same tag keeps its source,
    /// so editing the amount of a rule-tagged transaction does not make it
    /// manual, and saving a dismissed transaction without a tag keeps it
    /// dismissed.</summary>
    let onUpdate
        (isTransfer : bool)
        (tagId : Guid option)
        (current : Categorisation option)
        : Categorisation option =
        match isTransfer, tagId, current with
        | true, _, Some (Categorisation.Transfer _) -> current
        | true, _, _ -> Some (Categorisation.Transfer Source.Manual)
        | false, None, Some Categorisation.Dismissed -> current
        | false, None, _ -> None
        | false, Some tagId, Some (Categorisation.Tagged (currentTagId, _)) when
            currentTagId = tagId
            ->
            current
        | false, Some tagId, _ -> Some (manual tagId)

    /// <summary>Tag untagged: an untagged transaction gets the applied
    /// proposal, if any (<c>Policy.applyRule</c>). A tagged, dismissed, or
    /// transfer transaction keeps its categorisation.</summary>
    let tagUntagged
        (applied : Categorisation option)
        (current : Categorisation option)
        : Categorisation option =
        match current with
        | None -> applied
        | Some _ -> current

    /// <summary>Re-tag: an untagged transaction, or one whose source is a
    /// rule, gets the applied proposal (<c>Policy.applyRule</c>), or becomes
    /// untagged when there is none: no rule wins, or the winner's proposal is
    /// only suggested. Any other source is a decision that never
    /// changes.</summary>
    let retag
        (applied : Categorisation option)
        (current : Categorisation option)
        : Categorisation option =
        match current with
        | Some categorisation when source categorisation <> Source.Rule ->
            current
        | Some _
        | None -> applied

    /// <summary>Who decided a quick tag choice: the user, accepting the row's
    /// suggestion or not. The client says which button was the suggestion. See
    /// decision 6 in docs/transfer-rules.md.</summary>
    let private chosen (suggested : bool) =
        if suggested then Source.Accepted else Source.Manual

    /// <summary>Quick tagging with a tag replaces whatever the transaction had
    /// with the user's tag, accepted when it was the suggestion. See decision 1
    /// in docs/quick-tagging.md.</summary>
    let onQuickTag (tagId : Guid) (suggested : bool) : Categorisation option =
        Some (Categorisation.Tagged (tagId, chosen suggested))

    /// <summary>Dismissing records that the transaction has no tag, whatever it
    /// had.</summary>
    let onDismiss : Categorisation option = Some Categorisation.Dismissed

    /// <summary>Marking a transaction as a transfer from quick tagging replaces
    /// whatever it had, accepted when it was the suggestion.</summary>
    let onTransfer (suggested : bool) : Categorisation option =
        Some (Categorisation.Transfer (chosen suggested))

    /// <summary>Import's account-number detection marks a new transaction as
    /// a detected transfer. See decision 9 in docs/csv-import.md.</summary>
    let onDetectTransfer : Categorisation option =
        Some (Categorisation.Transfer Source.Detected)

/// <summary>Which proposals are applied without the user; the rest are only
/// suggested in quick tagging. A transfer leaves the income statement and the
/// queue at once, so a wrong one would hide money; a wrong tag still shows on
/// the dashboard. Import's detected transfers are always applied
/// (<c>Categorisation.onDetectTransfer</c>). See decision 3 in
/// docs/transfer-rules.md.</summary>
module Policy =
    /// <summary>The categorisation a winning rule applies: its tag, with the
    /// rule source. A rule's transfer is not applied: it is only
    /// suggested.</summary>
    let applyRule (target : RuleTarget) : Categorisation option =
        match target with
        | RuleTarget.Tag tagId ->
            Some (Categorisation.Tagged (tagId, Source.Rule))
        | RuleTarget.Transfer -> None
