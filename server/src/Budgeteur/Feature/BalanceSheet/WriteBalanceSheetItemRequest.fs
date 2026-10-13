namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.Side
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>Payload for creating or updating a balance sheet item.</summary>
type WriteBalanceSheetItemRequest = {
    /// <summary>A human-readable name, e.g. "Chequing account" or
    /// "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability.</summary>
    [<SchemaHint.Enum(typeof<Side>)>]
    Side : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's value. Direction is
    /// implied by Side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Value : decimal

    /// <summary>The date the value is accurate as of. At most one day after
    /// the server's UTC date.</summary>
    AsOf : DateOnly
}

module WriteBalanceSheetItemRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Domain.AsOfDate
    open Budgeteur.Shared.DomainError

    /// <summary>Validate the request as of the instant <c>now</c>, which bounds
    /// the as-of date.</summary>
    let validate
        (now : DateTimeOffset)
        (req : WriteBalanceSheetItemRequest)
        (id : Guid)
        =
        validation {
            let! name = ItemName.create req.Name
            and! value = Value.create req.Value
            and! asOf = AsOfDate.validate now req.AsOf

            and! side = Side.parse req.Side |> Result.mapError ValidationFailed

            and! term = Term.parse req.Term |> Result.mapError ValidationFailed

            let item : BalanceSheetItem = {
                Id = id
                Name = name
                Side = side
                Term = term
                Value = value
                AsOf = asOf
            }

            return item
        }
        |> DomainError.joinValidationErrors
