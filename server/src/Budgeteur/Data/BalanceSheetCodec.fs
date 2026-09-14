namespace Budgeteur.Data

module BalanceSheetCodec =
    open System
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Domain.BalanceSheetItem

    let toRow (sheetId : Guid) (sheet : BalanceSheet) (userId : string) : main.BalanceSheets = {
        Id = sheetId
        UserId = userId
        StatementDate = sheet.StatementDate
    }

    let fromRow (row : main.BalanceSheets) (items : BalanceSheetItem list) : BalanceSheet = {
        StatementDate = row.StatementDate
        Items = items
    }
