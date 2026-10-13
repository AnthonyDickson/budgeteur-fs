namespace Budgeteur.Domain.BalanceSheetItem

open System

open Budgeteur.Domain.Money
open Budgeteur.Domain.Side
open Budgeteur.Domain.Term
open Budgeteur.Shared.DomainError

type ItemName = private ItemName of string

module ItemName =
    [<Literal>]
    let internal MaxLength = 128

    let private nonEmpty (name : string) =
        if String.IsNullOrWhiteSpace name then
            Error (
                ValidationFailed "Item name cannot be null or just whitespace"
            )
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxLength then
            Error (
                ValidationFailed
                    $"Item name is too long. Names must be at most \
                    %i{MaxLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    /// <summary>Trim whitespace and then validate an item name. Returns the
    /// trimmed name.</summary>
    let create (name : string) =
        name.Trim ()
        |> nonEmpty
        |> Result.bind acceptableLength
        |> Result.map ItemName

    let value (ItemName name) = name

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromString name = ItemName name

/// <summary>
/// An item's value as a positive magnitude. The direction of the value is
/// implied by the owning item's <see cref="Side"/>, so a magnitude can never
/// disagree with its classification. An account's balance is signed instead;
/// see <c>Budgeteur.Domain.Account</c>.
/// </summary>
type Value = private Value of decimal

module Value =
    let private nonNegative (amount : decimal) =
        if amount < 0m then
            Error (
                ValidationFailed
                    "Value must be a positive magnitude. Use Side to record \
                    whether the amount is an asset or a liability."
            )
        else
            Ok amount

    /// <summary>Round to cents and validate that the value is a positive
    /// magnitude.</summary>
    let create (amount : decimal) =
        amount
        |> nonNegative
        |> Result.map Money.roundToCents
        |> Result.map Value

    let value (Value amount) = amount

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromDecimal amount = Value amount

/// <summary>A single line on the balance sheet that is not an account: one
/// asset or one liability. Its values are observations.</summary>
type BalanceSheetItem = {
    /// <summary>Unique identifier for the item.</summary>
    Id : Guid

    /// <summary>A human-readable name, e.g. "House" or "Mortgage".</summary>
    Name : ItemName

    /// <summary>Whether the item is an asset or a liability. Fixed at
    /// creation.</summary>
    Side : Side

    /// <summary>Whether the item is current or non-current.</summary>
    Term : Term

    /// <summary>The date the item was sold or repaid, or none while it is
    /// held. See decision 4 in docs/reports.md.</summary>
    ClosedOn : DateOnly option
}

/// <summary>A value an item had as of a date, entered by hand. An item has at
/// most one observation per date: a new one replaces any on its date. See
/// decision 2 in docs/reports.md.</summary>
type ItemObservation = {
    AsOf : DateOnly

    /// <summary>The positive magnitude of the item's value. Direction is
    /// implied by the item's Side.</summary>
    Value : Value
}

/// <summary>An item and its current value.</summary>
type ItemValue = {
    Item : BalanceSheetItem

    /// <summary>The observation with the latest as-of date. Every item has
    /// one: it is created with its first.</summary>
    Current : ItemObservation
}
