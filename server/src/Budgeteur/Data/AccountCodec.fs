namespace Budgeteur.Data

module AccountCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account
    open Budgeteur.Domain.Term

    let toRow (account : Account) (userId : string) : main.Accounts = {
        Id = account.Id
        UserId = userId
        Number = account.Number |> Option.map AccountNumber.value
        Name = AccountName.value account.Name
        Term = Term.toString account.Term
    }

    let fromRow (row : main.Accounts) : Account = {
        Id = row.Id
        Number = row.Number |> Option.map AccountNumber.unsafeFromString
        Name = AccountName.unsafeFromString row.Name
        Term =
            match Term.parse row.Term with
            | Ok term -> term
            // The database checks this column, so in practice this arm is
            // unreachable
            | Error error -> failwith error
    }
