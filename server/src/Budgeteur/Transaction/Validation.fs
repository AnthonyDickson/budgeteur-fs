namespace Budgeteur.Transaction

module Validation =
    open Budgeteur.DomainError

    [<Literal>]
    let private MaxTransactionDescriptionLength = 256

    let private nonEmpty (description : string) =
        if System.String.IsNullOrWhiteSpace description then
            Error (ValidationFailed "Description cannot be null or just whitespace")
        else
            Ok description

    let private acceptableLength (description : string) =
        if description.Length > MaxTransactionDescriptionLength then
            Error (
                ValidationFailed
                    $"Title is too long. Titles must be at most \
                    %i{MaxTransactionDescriptionLength} characters, but got %i{description.Length}"
            )
        else
            Ok description

    /// <summary>Trim whitespace and then validate a transaction description. Returns the trimmed title.</summary>
    let validateAndTrimDescription (description : string) =
        description.Trim () |> nonEmpty |> Result.bind acceptableLength
