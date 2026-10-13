namespace Budgeteur.Data

module AccountBalanceCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account
    open Budgeteur.Domain.Money

    /// <summary>An account row left joined to its row in the current balances
    /// view. A view's columns are nullable to SqlHydra, so an unmatched join
    /// and a missing column both read as an unknown balance.</summary>
    let fromRow
        (account : main.Accounts, current : main.LeftJoined.CurrentBalances)
        : AccountBalance = {
        Account = AccountCodec.fromRow account
        Current =
            match current.AsOf, current.Balance with
            | Some asOf, Some balance ->
                Some {
                    AsOf = asOf
                    Balance = Money.unsafeFromDecimal balance
                }
            | _ -> None
    }
