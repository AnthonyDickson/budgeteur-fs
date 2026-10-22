namespace Budgeteur.Domain.Rule

open System

open Budgeteur.Domain.Transaction
open Budgeteur.Shared.DomainError

type RulePattern = private RulePattern of string

module RulePattern =
    [<Literal>]
    let private MaxPatternLength = 128

    let private nonEmpty (pattern : string) =
        if String.IsNullOrWhiteSpace pattern then
            Error (ValidationFailed "Rule pattern cannot be null or whitespace")
        else
            Ok pattern

    let private acceptableLength (pattern : string) =
        if pattern.Length > MaxPatternLength then
            Error (
                ValidationFailed
                    $"Rule pattern is too long. Patterns must be at most \
                    %i{MaxPatternLength} characters, but got %i{pattern.Length}"
            )
        else
            Ok pattern

    /// <summary>Trim whitespace and then validate a rule pattern. Returns the
    /// trimmed pattern.</summary>
    let create (pattern : string) =
        pattern.Trim ()
        |> nonEmpty
        |> Result.bind acceptableLength
        |> Result.map RulePattern

    let value (RulePattern pattern) = pattern

    /// <summary>How patterns and descriptions are compared: ordinal, ignoring
    /// case. Culture-sensitive comparison depends on the server's culture and
    /// ICU version, and treats some characters as ignorable, so a pattern of
    /// only a soft hyphen would match every description.</summary>
    let comparison = StringComparison.OrdinalIgnoreCase

    /// <summary>Whether two patterns are the same under the comparison.
    /// Patterns are unique per user by this equality.</summary>
    let same (RulePattern a) (RulePattern b) = String.Equals (a, b, comparison)

    /// <summary>Whether the pattern occurs anywhere in the description under
    /// the comparison.</summary>
    let matches (description : TransactionDescription) (RulePattern pattern) =
        (TransactionDescription.value description).Contains(pattern, comparison)

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromString pattern = RulePattern pattern

/// <summary>What a rule proposes when it wins: a tag, or a transfer. A
/// transfer has no tag, so a transfer rule with a tag cannot be expressed. See
/// decision 1 in docs/transfer-rules.md.</summary>
[<RequireQualifiedAccess>]
type RuleTarget =
    | Tag of tagId : Guid
    | Transfer

/// <summary>A target crosses the API and the database as a kind (<c>Tag</c> or
/// <c>Transfer</c>) and an optional tag id, since the OpenAPI document cannot
/// describe a union with fields. See decision 9 in
/// docs/transfer-rules.md.</summary>
module RuleTarget =
    [<Literal>]
    let TagKind = "Tag"

    [<Literal>]
    let TransferKind = "Transfer"

    /// <summary>The target from its kind and tag id. A tag target needs a tag
    /// id and a transfer target rejects one.</summary>
    let create
        (kind : string)
        (tagId : Guid option)
        : Result<RuleTarget, DomainError> =
        match kind, tagId with
        | TagKind, Some tagId -> Ok (RuleTarget.Tag tagId)
        | TagKind, None ->
            Error (ValidationFailed "A tag target needs a tag id")
        | TransferKind, None -> Ok RuleTarget.Transfer
        | TransferKind, Some _ ->
            Error (ValidationFailed "A transfer cannot have a tag")
        | other, _ ->
            Error (
                ValidationFailed
                    $"\"{other}\" is not a valid target, expecting one of \
                    \"Tag\" or \"Transfer\"."
            )

    let kind (target : RuleTarget) : string =
        match target with
        | RuleTarget.Tag _ -> TagKind
        | RuleTarget.Transfer -> TransferKind

    let tagId (target : RuleTarget) : Guid option =
        match target with
        | RuleTarget.Tag tagId -> Some tagId
        | RuleTarget.Transfer -> None

type Rule = {
    Id : Guid
    Pattern : RulePattern
    Target : RuleTarget
}

module Rule =
    /// <summary>Orders rules by precedence: longer patterns first, then equal
    /// lengths by the comparison. The final ordinal step only separates
    /// patterns that differ by case alone, which uniqueness rules out, so the
    /// order never depends on the order of the input.</summary>
    let private precedence (a : Rule) (b : Rule) =
        let a = RulePattern.value a.Pattern
        let b = RulePattern.value b.Pattern

        match compare b.Length a.Length with
        | 0 ->
            match String.Compare (a, b, RulePattern.comparison) with
            | 0 -> String.CompareOrdinal (a, b)
            | order -> order
        | order -> order

    /// <summary>The winning rule for a description: the matching rule with the
    /// longest pattern, whatever its target, with equal lengths ordered by the
    /// comparison. None when no rule matches. Apply it to the rules once and
    /// reuse the result for many descriptions, so the rules are sorted
    /// once.</summary>
    let winner (rules : Rule list) : TransactionDescription -> Rule option =
        let rules = List.sortWith precedence rules

        fun description ->
            rules
            |> List.tryFind (fun rule ->
                RulePattern.matches description rule.Pattern)
