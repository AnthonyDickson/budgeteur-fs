namespace Budgeteur.Feature.Account

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.Account
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>A balance entered by hand, recorded as an observation.</summary>
type BalanceEntryRequest = {
    /// <summary>Signed: positive is held, negative is owed.</summary>
    Balance : decimal

    /// <summary>The date the balance is accurate as of. At most one day after
    /// the server's UTC date. Replaces any balance on the same date.</summary>
    AsOf : DateOnly
}

/// <summary>Payload for creating or updating an account.</summary>
type WriteAccountRequest = {
    /// <summary>The user's alias for the account.</summary>
    [<MinLength(1)>]
    [<MaxLength(AccountName.MaxLength)>]
    Name : string

    /// <summary>The number statements identify the account by: an NZ bank
    /// account number or a masked card number. None, or blank, for an account
    /// without one.</summary>
    Number : string option

    /// <summary>Whether the account is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>A new balance to record, or none to leave the balance
    /// history as it is.</summary>
    Balance : BalanceEntryRequest option
}

module WriteAccountRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Shared.DomainError

    let private number (number : string option) =
        match number with
        | Some number when not (String.IsNullOrWhiteSpace number) ->
            AccountNumber.create number |> Result.map Some
        | _ -> Ok None

    let private balance (now : DateTimeOffset) (entry : BalanceEntryRequest) =
        BalanceObservation.create now entry.AsOf entry.Balance

    /// <summary>Validate the request as of the instant <c>now</c>, which bounds
    /// the balance's as-of date. Returns the account and the balance to record,
    /// if any.</summary>
    let validate
        (now : DateTimeOffset)
        (req : WriteAccountRequest)
        (id : Guid)
        =
        validation {
            let! name = AccountName.create req.Name
            and! number = number req.Number

            and! term = Term.parse req.Term |> Result.mapError ValidationFailed

            and! observation =
                req.Balance |> Option.traverseResult (balance now)

            let account : Account = {
                Id = id
                Number = number
                Name = name
                Term = term
            }

            return account, observation
        }
        |> DomainError.joinValidationErrors
