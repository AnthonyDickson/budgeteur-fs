namespace Budgeteur.Data

module BalanceSheetItemCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem
    open Budgeteur.Domain.Side
    open Budgeteur.Domain.Term

    let toRow
        (item : BalanceSheetItem)
        (userId : string)
        : main.BalanceSheetItems = {
        Id = item.Id
        UserId = userId
        Name = ItemName.value item.Name
        Side = Side.toString item.Side
        Term = Term.toString item.Term
        ClosedOn = item.ClosedOn
    }

    let fromRow (row : main.BalanceSheetItems) : BalanceSheetItem = {
        Id = row.Id
        Name = ItemName.unsafeFromString row.Name
        Side =
            match Side.parse row.Side with
            | Ok side -> side
            // The database checks this column, so in practice this arm is
            // unreachable
            | Error error -> failwith error
        Term =
            match Term.parse row.Term with
            | Ok term -> term
            // The database checks this column, so in practice this arm is
            // unreachable
            | Error error -> failwith error
        ClosedOn = row.ClosedOn
    }
