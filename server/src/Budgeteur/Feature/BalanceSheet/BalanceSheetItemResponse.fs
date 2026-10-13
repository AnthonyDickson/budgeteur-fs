namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.Side
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>A balance sheet item with its current value.</summary>
type BalanceSheetItemResponse = {
    /// <summary>Unique identifier for the item.</summary>
    Id : Guid

    /// <summary>A human-readable name, e.g. "House" or "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability.</summary>
    [<SchemaHint.Enum(typeof<Side>)>]
    Side : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's current value: its latest
    /// observation. Direction is implied by Side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Value : decimal

    /// <summary>The date the current value is accurate as of.</summary>
    AsOf : DateOnly
}

module BalanceSheetItemResponse =
    let fromDomain (item : ItemValue) : BalanceSheetItemResponse = {
        Id = item.Item.Id
        Name = ItemName.value item.Item.Name
        Side = Side.toString item.Item.Side
        Term = Term.toString item.Item.Term
        Value = Value.value item.Current.Value
        AsOf = item.Current.AsOf
    }
