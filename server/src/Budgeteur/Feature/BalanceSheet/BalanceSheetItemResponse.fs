namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Shared.OpenApi

/// <summary>A single line on the balance sheet: one asset or one
/// liability.</summary>
type BalanceSheetItemResponse = {
    /// <summary>Unique identifier for the item.</summary>
    Id : Guid

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

    /// <summary>The date the balance is accurate as of.</summary>
    AsOf : DateOnly
}

module BalanceSheetItemResponse =
    let fromDomain (item : BalanceSheetItem) : BalanceSheetItemResponse = {
        Id = item.Id
        Name = ItemName.value item.Name
        Kind = ItemKind.toString item.Kind
        Term = Term.toString item.Term
        Balance = Balance.value item.Balance
        AsOf = item.AsOf
    }
