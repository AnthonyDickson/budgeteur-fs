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

type Rule = {
    Id : Guid
    Pattern : RulePattern
    TagId : Guid
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
    /// longest pattern, with equal lengths ordered by the comparison. None when
    /// no rule matches. Apply it to the rules once and reuse the result for
    /// many descriptions, so the rules are sorted once.</summary>
    let winner (rules : Rule list) : TransactionDescription -> Rule option =
        let rules = List.sortWith precedence rules

        fun description ->
            rules
            |> List.tryFind (fun rule ->
                RulePattern.matches description rule.Pattern)
