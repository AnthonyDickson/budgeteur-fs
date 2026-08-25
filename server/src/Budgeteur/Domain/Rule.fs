namespace Budgeteur.Domain.Rule

open System

open Budgeteur.Shared.DomainError

type Rule = {
    Id : Guid
    Pattern : string
    TagId : Guid
}

module Validation =
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
    let validateAndTrimPattern (pattern : string) =
        pattern.Trim () |> nonEmpty |> Result.bind acceptableLength
