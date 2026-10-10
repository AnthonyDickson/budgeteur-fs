namespace Budgeteur.Feature.Transaction

module TransactionCodec =
    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Transaction
    open Budgeteur.Shared.Money

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
        IsTransfer = transaction.IsTransfer
        AccountId = transaction.AccountId
        ImportHash = importHash
    }

    let fromRow (row : main.Transactions) : Transaction = {
        Id = row.Id
        Amount = Money.unsafeFromDecimal row.Amount
        Description = TransactionDescription.unsafeFromString row.Description
        Date = row.Date
        IsTransfer = row.IsTransfer
        AccountId = row.AccountId
    }

    /// <summary>Read a transaction left-joined with its assignment: the
    /// slice's read shape, a transaction and its tag, if any.</summary>
    let fromJoinedRow
        (row : main.Transactions, assignment : main.LeftJoined.TagAssignments)
        =
        fromRow row,
        assignment.ToOption () |> Option.map TagAssignmentCodec.fromRow
