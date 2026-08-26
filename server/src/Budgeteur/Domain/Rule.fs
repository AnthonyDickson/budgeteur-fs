namespace Budgeteur.Domain.Rule

open System

open Budgeteur.Shared.DomainError

type RulePattern = private RulePattern of string

module RulePattern =
    [<Literal>]
    let private MaxPatternLength = 256

    let private nonEmpty (pattern : string) =
        if System.String.IsNullOrWhiteSpace pattern then
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

    /// <summary>Trim whitespace and then validate a rule pattern. Returns the trimmed pattern.</summary>
    let create (pattern : string) =
        pattern.Trim ()
        |> nonEmpty
        |> Result.bind acceptableLength
        |> Result.map RulePattern

    let value (RulePattern pattern) = pattern

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromString pattern = RulePattern pattern

type Rule = {
    Id : Guid
    Pattern : RulePattern
    TagId : Guid
}
