namespace Budgeteur.Transaction

open System

/// <summary>A transaction stored in the database.</summary>
type Transaction = {
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
    AccountId : Option<Guid>

    /// <summary>The type of transaction.</summary>
    CategoryId : Option<Guid>
}

module Transaction =
    open Thoth.Json.Net

    open Budgeteur.Db

    let toRow (transaction : Transaction) (userId : string) (importHash : Option<string>) : main.Transactions = {
        Id = transaction.Id
        UserId = userId
        Amount = transaction.Amount
        Description = transaction.Description
        Date = transaction.Date
        IsTransfer = transaction.IsTransfer
        AccountId = transaction.AccountId
        ImportHash = importHash
        CategoryId = transaction.CategoryId
    }

    let fromRow (row : main.Transactions) : Transaction = {
        Id = row.Id
        Amount = row.Amount
        Description = row.Description
        Date = row.Date
        IsTransfer = row.IsTransfer
        AccountId = row.AccountId
        CategoryId = row.CategoryId
    }
