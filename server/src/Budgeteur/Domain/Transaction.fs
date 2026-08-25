namespace Budgeteur.Domain.Transaction

open System

open Budgeteur.Shared.DomainError

/// <summary>A transaction stored in the database.</summary>
type Transaction = {
    /// <summary>Unique identifier for the transaction item.</summary>
    Id : Guid

    /// <summary>A debit (negative) or credit (positive). Serialised as a string.</summary>
    Amount : decimal

    /// <summary>The title or description of the transaction.</summary>
    Description : string

    /// <summary>Date when the transaction occurred (UTC).</summary>
    Date : DateOnly

    /// <summary>Whether the transaction represents an internal transfer between one's own accounts.</summary>
    IsTransfer : bool

    /// <summary>The bank account associated with this transaction.</summary>
    AccountId : Guid option

    /// <summary>The category of transaction.</summary>
    TagId : Guid option
}

module Validation =
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
