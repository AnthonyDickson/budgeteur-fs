namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Shared.OpenApi

/// <summary>Payload for creating or updating a balance sheet item.</summary>
type WriteBalanceSheetItemRequest = {
    /// <summary>A human-readable name, e.g. "Chequing account" or
    /// "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability.</summary>
    [<SchemaHint.Enum(typeof<ItemKind>)>]
    Kind : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's value. Direction is
    /// implied by Kind.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Balance : decimal
}

module WriteBalanceSheetItemRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Shared.DomainError

    let private joinValidationErrors
        (validationResult : Validation<'Ok, DomainError>)
        : Result<'Ok, DomainError> =
        match validationResult with
        | Ok value -> Ok value
        | Error errors ->
            errors
            |> List.map (fun error ->
                match error with
                | ValidationFailed error -> error
                // TODO: Is there a way to remove this exception? Maybe have the
                // validation functions return a scalar value (e.g. just a
                // string)? It would be nice if this could have nice error
                // messages like Thoth.
                | other -> failwithf $"unexpected domain error: {other}")
            |> fun errorStrings ->
                "Validation failed:\n\t" + String.Join ("\n\t", errorStrings)
            |> ValidationFailed
            |> Error

    let validate (req : WriteBalanceSheetItemRequest) (id : Guid) =
        validation {
            let! name = ItemName.create req.Name
            and! balance = Balance.create req.Balance

            and! kind =
                ItemKind.parse req.Kind |> Result.mapError ValidationFailed

            and! term = Term.parse req.Term |> Result.mapError ValidationFailed

            let item : BalanceSheetItem = {
                Id = id
                Name = name
                Kind = kind
                Term = term
                Balance = balance
            }

            return item
        }
        |> joinValidationErrors
