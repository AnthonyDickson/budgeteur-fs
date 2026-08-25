namespace Budgeteur.Domain.Tag

open System

open Budgeteur.Shared.DomainError

type Tag = { Id : Guid; Name : string }

module Validation =
    [<Literal>]
    let private MaxNameLength = 256

    let private nonEmpty (name : string) =
        if System.String.IsNullOrWhiteSpace name then
            Error (ValidationFailed "Tag name cannot be null or whitespace")
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxNameLength then
            Error (
                ValidationFailed
                    $"Name is too long. Names must be at most \
                    %i{MaxNameLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    /// <summary>Trim whitespace and then validate a tag name. Returns the trimmed name.</summary>
    let validateAndTrimName (name : string) =
        name.Trim () |> nonEmpty |> Result.bind acceptableLength
