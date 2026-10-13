namespace Budgeteur.Feature.BalanceSheet

open System

open Budgeteur.Domain.Side
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>An account with a known balance, as a balance sheet line. Its side
/// follows the sign of its current balance.</summary>
type AccountLineResponse = {
    /// <summary>The account's id.</summary>
    Id : Guid

    /// <summary>The user's alias for the account.</summary>
    Name : string

    /// <summary>The number statements identify the account by, if
    /// any.</summary>
    Number : string option

    /// <summary>Asset when the balance is zero or more, liability when it is
    /// negative.</summary>
    [<SchemaHint.Enum(typeof<Side>)>]
    Side : string

    /// <summary>Whether the account is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The magnitude of the current balance. Direction is implied by
    /// Side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Balance : decimal

    /// <summary>The date the current balance is accurate as of.</summary>
    AsOf : DateOnly
}

/// <summary>An account whose balance is unknown: it has no observations. It is
/// left out of the totals.</summary>
type UnknownBalanceResponse = {
    /// <summary>The account's id.</summary>
    Id : Guid

    /// <summary>The user's alias for the account.</summary>
    Name : string

    /// <summary>The number statements identify the account by, if
    /// any.</summary>
    Number : string option

    /// <summary>Whether the account is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string
}

module AccountLineResponse =
    open Budgeteur.Domain.Account
    open Budgeteur.Domain.BalanceSheet

    /// <summary>The account's line, or none when its balance is
    /// unknown.</summary>
    let fromDomain (account : AccountBalance) : AccountLineResponse option =
        account.Current
        |> Option.map (fun current ->
            let side, balance = BalanceSheet.accountSide current.Balance

            {
                Id = account.Account.Id
                Name = AccountName.value account.Account.Name
                Number =
                    account.Account.Number |> Option.map AccountNumber.value
                Side = Side.toString side
                Term = Term.toString account.Account.Term
                Balance = balance
                AsOf = current.AsOf
            })

module UnknownBalanceResponse =
    open Budgeteur.Domain.Account

    let fromDomain (account : Account) : UnknownBalanceResponse = {
        Id = account.Id
        Name = AccountName.value account.Name
        Number = account.Number |> Option.map AccountNumber.value
        Term = Term.toString account.Term
    }
