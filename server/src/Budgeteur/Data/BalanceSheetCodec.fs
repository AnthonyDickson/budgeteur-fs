namespace Budgeteur.Data

module BalanceSheetCodec =
    open System
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Domain.BalanceSheetItem

    let fromRow (row : main.BalanceSheets) (items : BalanceSheetItem list) : BalanceSheet = {
        StatementDate = DateTime.SpecifyKind (row.StatementDate, DateTimeKind.Utc)
        Items = items
    }
