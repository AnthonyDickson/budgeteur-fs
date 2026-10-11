namespace Budgeteur.Feature.Account

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.Account
open Budgeteur.Domain.Money
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>An account's current balance: its latest observation.</summary>
type AccountBalanceResponse = {
    /// <summary>Signed: positive is held, negative is owed.</summary>
    Balance : decimal

    /// <summary>The date the balance is accurate as of.</summary>
    AsOf : DateOnly
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
}

module AccountResponse =
    let fromDomain
        (account : Account)
        (current : BalanceObservation option)
        : AccountResponse = {
        Id = account.Id
        Name = AccountName.value account.Name
        Number = account.Number |> Option.map AccountNumber.value
        Term = Term.toString account.Term
        Balance =
            current
            |> Option.map (fun observation -> {
                Balance = Money.value observation.Balance
                AsOf = observation.AsOf
            })
    }
