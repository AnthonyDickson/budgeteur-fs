namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.Side
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>A value entered by hand, recorded as an observation.</summary>
type ItemObservationRequest = {
    /// <summary>The positive magnitude of the item's value. Direction is
    /// implied by the item's side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Value : decimal

    /// <summary>The date the value is accurate as of. At most one day after the
    /// server's UTC date. Replaces any value on the same date.</summary>
    AsOf : DateOnly
}

/// <summary>Payload for creating a balance sheet item with its first value.
/// The id is generated server-side.</summary>
type CreateBalanceSheetItemRequest = {
    /// <summary>A human-readable name, e.g. "House" or "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability. Fixed at
    /// creation.</summary>
    [<SchemaHint.Enum(typeof<Side>)>]
    Side : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's first value. Direction is
    /// implied by Side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Value : decimal

    /// <summary>The date the first value is accurate as of. At most one day
    /// after the server's UTC date.</summary>
    AsOf : DateOnly
}

/// <summary>Payload for updating a balance sheet item's details. Its side is
/// fixed at creation, and its values are observations.</summary>
type UpdateBalanceSheetItemRequest = {
    /// <summary>A human-readable name, e.g. "House" or "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string
}

/// <summary>Validation shared by the slice's item requests.</summary>
module ItemRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Domain.AsOfDate
    open Budgeteur.Shared.DomainError

    let private observation
        (now : DateTimeOffset)
        (value : decimal)
        (asOf : DateOnly)
        : Validation<ItemObservation, DomainError> =
        validation {
            let! value = Value.create value
            and! asOf = AsOfDate.validate now asOf
            return { AsOf = asOf; Value = value }
        }

    /// <summary>Validate a value entry as of the instant <c>now</c>, which
    /// bounds its as-of date.</summary>
    let validateObservation
        (now : DateTimeOffset)
        (req : ItemObservationRequest)
        : Result<ItemObservation, DomainError> =
        observation now req.Value req.AsOf |> DomainError.joinValidationErrors

    /// <summary>Validate a create request as of the instant <c>now</c>.
    /// Returns the item and its first observation.</summary>
    let validateCreate
        (now : DateTimeOffset)
        (req : CreateBalanceSheetItemRequest)
        (id : Guid)
        : Result<BalanceSheetItem * ItemObservation, DomainError> =
        validation {
            let! name = ItemName.create req.Name
            and! side = Side.parse req.Side |> Result.mapError ValidationFailed
            and! term = Term.parse req.Term |> Result.mapError ValidationFailed
            and! first = observation now req.Value req.AsOf

            let item : BalanceSheetItem = {
                Id = id
                Name = name
                Side = side
                Term = term
            }

            return item, first
        }
        |> DomainError.joinValidationErrors

    /// <summary>Validate an update request against the item it changes, which
    /// keeps its id and side.</summary>
    let validateUpdate
        (existing : BalanceSheetItem)
        (req : UpdateBalanceSheetItemRequest)
        : Result<BalanceSheetItem, DomainError> =
        validation {
            let! name = ItemName.create req.Name
            and! term = Term.parse req.Term |> Result.mapError ValidationFailed

            return {
                existing with
                    Name = name
                    Term = term
            }
        }
        |> DomainError.joinValidationErrors
