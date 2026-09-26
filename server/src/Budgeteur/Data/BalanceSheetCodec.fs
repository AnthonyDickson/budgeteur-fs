namespace Budgeteur.Data

module BalanceSheetCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Domain.BalanceSheetItem

    let fromRow (row : main.BalanceSheets) (items : BalanceSheetItem list) : BalanceSheet = {
        StatementDate = UtcDateTime.fromColumn row.StatementDate
        Items = items
    }
