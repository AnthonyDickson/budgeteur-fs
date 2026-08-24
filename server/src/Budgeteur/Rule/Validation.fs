namespace Budgeteur.Rule

module Validation =
    open Budgeteur.DomainError

    [<Literal>]
    let private MaxPatternLength = 256

    let private nonEmpty (name : string) =
        if System.String.IsNullOrWhiteSpace name then
            Error (ValidationFailed "Rule pattern cannot be null or whitespace")
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxPatternLength then
            Error (
                ValidationFailed
                    $"Rule pattern is too long. Patterns must be at most \
                    %i{MaxPatternLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    /// <summary>Trim whitespace and then validate a rule pattern. Returns the trimmed pattern.</summary>
    let validateAndTrimPattern (name : string) =
        name.Trim () |> nonEmpty |> Result.bind acceptableLength
