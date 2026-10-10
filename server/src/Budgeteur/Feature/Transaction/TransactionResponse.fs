namespace Budgeteur.Feature.Transaction

open System

open Budgeteur.Domain.TagAssignment
open Budgeteur.Shared.OpenApi

/// <summary>A transaction's tag and where it came from.</summary>
type TransactionTagResponse = {
    /// <summary>The tag's id.</summary>
    Id : Guid

    /// <summary>Whether the user set the tag or a rule did. Rules never change
    /// a manual tag.</summary>
    [<SchemaHint.Enum(typeof<TagSource>)>]
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

    /// <summary>The transaction's tag, or none when it is untagged.</summary>
    Tag : TransactionTagResponse option
}

module TransactionResponse =
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.Money

    let fromDomain
        (t : Transaction)
        (assignment : TagAssignment option)
        : TransactionResponse = {
        Id = t.Id
        Amount = Money.value t.Amount
        Description = TransactionDescription.value t.Description
        Date = t.Date
        IsTransfer = t.IsTransfer
        AccountId = t.AccountId
        Tag =
            assignment
            |> Option.map (fun assignment -> {
                Id = assignment.TagId
                Source = TagSource.toString assignment.Source
            })
    }
