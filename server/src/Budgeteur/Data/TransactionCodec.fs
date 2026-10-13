namespace Budgeteur.Data

module TransactionCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Transaction

    let toRow
        (transaction : Transaction)
        (userId : string)
        (importHash : string option)
        : main.Transactions = {
        Id = transaction.Id
        UserId = userId
        Amount = Money.value transaction.Amount
        Description = TransactionDescription.value transaction.Description
        Date = transaction.Date
        AccountId = transaction.AccountId
        ImportHash = importHash
    }

    let fromRow (row : main.Transactions) : Transaction = {
        Id = row.Id
        Amount = Money.unsafeFromDecimal row.Amount
        Description = TransactionDescription.unsafeFromString row.Description
        Date = row.Date
        AccountId = row.AccountId
    }
