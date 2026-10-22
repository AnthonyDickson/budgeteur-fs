namespace Budgeteur.Feature.Transaction

open System

open Budgeteur.Domain.Categorisation
open Budgeteur.Shared.OpenApi

/// <summary>A transaction's tag and where it came from.</summary>
type TransactionTagResponse = {
    /// <summary>The tag's id.</summary>
    Id : Guid

    /// <summary>Who decided the tag: the user without a suggestion (Manual)
    /// or by choosing one (Accepted), or a rule (Rule). Re-tag recomputes only
    /// rule tags. Detected is reserved for transfers, which have no
    /// tag.</summary>
    [<SchemaHint.Enum(typeof<Source>)>]
    Source : string
}

/// <summary>A transaction as returned by the API.</summary>
type TransactionResponse = {
    /// <summary>Unique identifier for the transaction item.</summary>
    Id : Guid

    /// <summary>A debit (negative) or credit (positive). Serialised as a
    /// string.</summary>
    Amount : decimal

    /// <summary>The title or description of the transaction.</summary>
    Description : string

    /// <summary>Date when the transaction occurred (UTC).</summary>
    Date : DateOnly

    /// <summary>Whether the transaction represents an internal transfer between
    /// one's own accounts.</summary>
    IsTransfer : bool

    /// <summary>The bank account associated with this transaction.</summary>
    AccountId : Guid option

    /// <summary>The name of the transaction's account, if it has one.</summary>
    AccountName : string option

    /// <summary>The transaction's tag, or none when it is untagged,
    /// dismissed, or a transfer.</summary>
    Tag : TransactionTagResponse option
}

module TransactionResponse =
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Transaction

    let fromDomain
        (t : Transaction)
        (categorisation : Categorisation option)
        (accountName : string option)
        : TransactionResponse = {
        Id = t.Id
        Amount = Money.value t.Amount
        Description = TransactionDescription.value t.Description
        Date = t.Date
        IsTransfer = Categorisation.isTransfer categorisation
        AccountId = t.AccountId
        AccountName = accountName
        Tag =
            match categorisation with
            | Some (Categorisation.Tagged (tagId, source)) ->
                Some {
                    Id = tagId
                    Source = Source.toString source
                }
            | Some Categorisation.Dismissed
            | Some (Categorisation.Transfer _)
            | None -> None
    }
