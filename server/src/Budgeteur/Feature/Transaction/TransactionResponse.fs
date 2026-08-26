namespace Budgeteur.Feature.Transaction

open System

/// <summary>A transaction as returned by the API.</summary>
type TransactionResponse = {
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

module TransactionResponse =
    open Budgeteur.Domain.Transaction

    let fromDomain (t : Transaction) : TransactionResponse = {
        Id = t.Id
        Amount = t.Amount
        Description = TransactionDescription.value t.Description
        Date = t.Date
        IsTransfer = t.IsTransfer
        AccountId = t.AccountId
        TagId = t.TagId
    }
