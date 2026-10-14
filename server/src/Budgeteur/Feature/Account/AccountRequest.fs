namespace Budgeteur.Feature.Account

open System

open Budgeteur.Domain.Account
open Budgeteur.Domain.Term

/// <summary>A balance entered by hand, recorded as an observation.</summary>
type BalanceEntryRequest = {
    /// <summary>Signed: positive is an asset (owned), negative a liability
    /// (owed).</summary>
    Balance : decimal

    /// <summary>The date the balance is accurate as of. At most one day after
    /// the server's UTC date. Replaces any balance on the same date.</summary>
    AsOf : DateOnly
}

/// <summary>Validation shared by the slice's requests.</summary>
module AccountRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Shared.DomainError

    let private parseNumber (number : string option) =
        match number with
        | Some number when not (String.IsNullOrWhiteSpace number) ->
            AccountNumber.create number |> Result.map Some
        | _ -> Ok None

    /// <summary>Validate an account's details: its name, number (blank is
    /// none), and term.</summary>
    let details
        (id : Guid)
        (name : string)
        (number : string option)
        (term : string)
        : Validation<Account, DomainError> =
        validation {
            let! name = AccountName.create name
            and! number = parseNumber number
            and! term = Term.parse term |> Result.mapError ValidationFailed

            return {
                Id = id
                Number = number
                Name = name
                Term = term
                ClosedOn = None
            }
        }

    /// <summary>Validate a balance entry as of the instant <c>now</c>, which
    /// bounds its as-of date.</summary>
    let balance (now : DateTimeOffset) (entry : BalanceEntryRequest) =
        BalanceObservation.create now entry.AsOf entry.Balance
