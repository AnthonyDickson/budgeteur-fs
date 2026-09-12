namespace Budgeteur.Domain.BalanceSheetItem

open System

open Budgeteur.Shared.DomainError
open Budgeteur.Shared.Money

type ItemName = private ItemName of string

module ItemName =
    [<Literal>]
    let private MaxItemNameLength = 128

    let private nonEmpty (name : string) =
        if String.IsNullOrWhiteSpace name then
            Error (ValidationFailed "Item name cannot be null or just whitespace")
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxItemNameLength then
            Error (
                ValidationFailed
                    $"Item name is too long. Names must be at most \
                    %i{MaxItemNameLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    /// <summary>Trim whitespace and then validate an item name. Returns the trimmed name.</summary>
    let create (name : string) =
        name.Trim () |> nonEmpty |> Result.bind acceptableLength |> Result.map ItemName

    let value (ItemName name) = name

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromString name = ItemName name

/// <summary>Whether an item is something owned (an asset) or owed (a liability).</summary>
type ItemKind =
    | Asset
    | Liability

/// <summary>
/// Whether an item is expected to be realised (assets) or settled (liabilities) within
/// the current accounting period, conventionally within about 12 months.
/// </summary>
type Term =
    | Current
    | NonCurrent

/// <summary>
/// An item's value as a positive magnitude. The direction of the value is implied by
/// the owning item's <see cref="ItemKind"/>, so a magnitude can never disagree with its
/// classification.
/// </summary>
type Balance = private Balance of decimal

module Balance =
    let private nonNegative (amount : decimal) =
        if amount < 0m then
            Error (
                ValidationFailed
                    "Balance must be a positive magnitude. Use ItemKind to record \
                    whether the amount is an asset or a liability."
            )
        else
            Ok amount

    /// <summary>Round to cents and then validate that the balance is a positive magnitude.</summary>
    let create (amount : decimal) =
        amount |> Money.roundToCents |> nonNegative |> Result.map Balance

    let value (Balance amount) = amount

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromDecimal amount = Balance amount

/// <summary>A single line on the balance sheet: one asset or one liability.</summary>
type BalanceSheetItem = {
    /// <summary>Unique identifier for the item.</summary>
    Id : Guid

    /// <summary>A human-readable name, e.g. "Chequing account" or "Mortgage".</summary>
    Name : ItemName

    /// <summary>Whether the item is an asset or a liability.</summary>
    Kind : ItemKind

    /// <summary>Whether the item is current or non-current.</summary>
    Term : Term

    /// <summary>The positive magnitude of the item's value. Direction is implied by Kind.</summary>
    Balance : Balance
}
