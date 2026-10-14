namespace Budgeteur.Feature.Account

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.Account
open Budgeteur.Domain.Money
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>An account's current balance: its latest observation.</summary>
type AccountBalanceResponse = {
    /// <summary>Signed: positive is an asset (owned), negative a liability
    /// (owed).</summary>
    Balance : decimal

    /// <summary>The date the balance is accurate as of.</summary>
    AsOf : DateOnly
}

/// <summary>An account as the slice reads it: with its current balance, and
/// any transactions dated after its close date.</summary>
type AccountDetails = {
    Balance : AccountBalance
    TransactionsAfterClose : TransactionsAfterClose option
}

/// <summary>A closed account's transactions after its close date.</summary>
type TransactionsAfterCloseResponse = {
    /// <summary>How many there are.</summary>
    Count : int

    /// <summary>The date of the latest.</summary>
    Latest : DateOnly
}

/// <summary>An account as returned by the API.</summary>
type AccountResponse = {
    Id : Guid

    /// <summary>The user's alias for the account.</summary>
    [<MinLength(1)>]
    [<MaxLength(AccountName.MaxLength)>]
    Name : string

    /// <summary>The number statements identify the account by, in canonical
    /// form. None for an account without one.</summary>
    Number : string option

    /// <summary>Whether the account is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The current balance, or none when the balance is
    /// unknown.</summary>
    Balance : AccountBalanceResponse option

    /// <summary>The date the account was closed, or none while it is
    /// open.</summary>
    ClosedOn : DateOnly option

    /// <summary>Transactions dated after the close date, or none. A closed
    /// account should have none, so they suggest the close date is wrong. See
    /// decision 4 in docs/reports.md.</summary>
    TransactionsAfterClose : TransactionsAfterCloseResponse option
}

module AccountResponse =
    let fromDomain (details : AccountDetails) : AccountResponse =
        let accountBalance = details.Balance
        let account = accountBalance.Account

        {
            Id = account.Id
            Name = AccountName.value account.Name
            Number = account.Number |> Option.map AccountNumber.value
            Term = Term.toString account.Term
            Balance =
                accountBalance.Current
                |> Option.map (fun observation -> {
                    Balance = Money.value observation.Balance
                    AsOf = observation.AsOf
                })
            ClosedOn = account.ClosedOn
            TransactionsAfterClose =
                details.TransactionsAfterClose
                |> Option.map (fun summary -> {
                    Count = summary.Count
                    Latest = summary.Latest
                })
        }
