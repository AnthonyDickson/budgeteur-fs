namespace Budgeteur.Data

module BalanceSheetItemCodec =
    open System
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem

    let toRow (item : BalanceSheetItem) (userId : string) : main.BalanceSheetItems = {
        Id = item.Id
        UserId = userId
        Name = ItemName.value item.Name
        Kind = ItemKind.toString item.Kind
        Term = Term.toString item.Term
        Balance = Balance.value item.Balance
    }

    let fromRow (row : main.BalanceSheetItems) : BalanceSheetItem = {
        Id = row.Id
        Name = ItemName.unsafeFromString row.Name
        Kind =
            match ItemKind.parse row.Kind with
            | Ok kind -> kind
            // The database checks this column, so in practice this arm is unreachable
            | Error error -> failwith error
        Term =
            match Term.parse row.Term with
            | Ok term -> term
            // The database checks this column, so in practice this arm is unreachable
            | Error error -> failwith error
        Balance = Balance.unsafeFromDecimal row.Balance
    }
