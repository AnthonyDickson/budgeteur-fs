namespace Budgeteur.Feature.Transaction

module TransactionCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Transaction

    let toRow (transaction : Transaction) (userId : string) (importHash : string option) : main.Transactions = {
        Id = transaction.Id
        UserId = userId
        Amount = transaction.Amount
        Description = TransactionDescription.value transaction.Description
        Date = transaction.Date
        IsTransfer = transaction.IsTransfer
        AccountId = transaction.AccountId
        ImportHash = importHash
        TagId = transaction.TagId
    }

    let fromRow (row : main.Transactions) : Transaction = {
        Id = row.Id
        Amount = row.Amount
        Description = TransactionDescription.unsafeFromString row.Description
        Date = row.Date
        IsTransfer = row.IsTransfer
        AccountId = row.AccountId
        TagId = row.TagId
    }
