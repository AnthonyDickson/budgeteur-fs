namespace Budgeteur.Domain.Account

open System
open System.Text.RegularExpressions

open Budgeteur.Domain.AsOfDate
open Budgeteur.Domain.Money
open Budgeteur.Domain.Term
open Budgeteur.Shared.DomainError

/// <summary>The number a statement identifies an account by: an NZ bank
/// account number in canonical form, or a masked card number as the statement
/// prints it. See decision 4 in docs/csv-import.md.</summary>
type AccountNumber = private AccountNumber of string

module AccountNumber =
    // [0-9] rather than \d, which also matches non-ASCII digits.

    /// <summary>Bank (2 digits), branch (4), account (up to 7), and suffix (2
    /// or 3), separated by hyphens or spaces.</summary>
    let private separated =
        Regex (
            "^([0-9]{2})[- ]([0-9]{4})[- ]([0-9]{1,7})[- ]([0-9]{2,3})$",
            RegexOptions.CultureInvariant
        )

    /// <summary>The same parts without separators, which needs the account
    /// part at its full seven digits to be unambiguous.</summary>
    let private unseparated =
        Regex (
            "^([0-9]{2})([0-9]{4})([0-9]{7})([0-9]{2,3})$",
            RegexOptions.CultureInvariant
        )

    /// <summary>Three or four groups of digits, some masked with X or *, e.g.
    /// XXXX-XXXX-XXXX-1234.</summary>
    let private maskedCard =
        Regex (
            "^(?=.*[Xx*])(?=.*[0-9])[0-9Xx*]{4,6}(?:[- ][0-9Xx*]{4,6}){2,3}$",
            RegexOptions.CultureInvariant
        )

    /// <summary>The canonical form of a bank account number: the account
    /// padded to seven digits and the suffix to three, joined by
    /// hyphens.</summary>
    let private canonical (parts : Match) =
        let part (index : int) (width : int) =
            parts.Groups[index].Value.PadLeft(width, '0')

        $"{part 1 2}-{part 2 4}-{part 3 7}-{part 4 3}"

    /// <summary>Parse an NZ bank account number into its canonical form, or
    /// accept a masked card number as printed. Surrounding whitespace is
    /// ignored.</summary>
    let create (number : string) : Result<AccountNumber, DomainError> =
        let number = number.Trim ()
        let separatedMatch = separated.Match number
        let unseparatedMatch = unseparated.Match number

        if separatedMatch.Success then
            Ok (AccountNumber (canonical separatedMatch))
        elif unseparatedMatch.Success then
            Ok (AccountNumber (canonical unseparatedMatch))
        elif maskedCard.IsMatch number then
            Ok (AccountNumber number)
        else
            Error (
                ValidationFailed
                    $"\"{number}\" is not an account number. Expected an NZ \
                    bank account number such as 12-3456-0789012-00, or a \
                    masked card number such as XXXX-XXXX-XXXX-1234."
            )

    let value (AccountNumber number) = number

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromString number = AccountNumber number

/// <summary>The user's alias for an account. Names need not be
/// unique.</summary>
type AccountName = private AccountName of string

module AccountName =
    [<Literal>]
    let internal MaxLength = 128

    let private nonEmpty (name : string) =
        if String.IsNullOrWhiteSpace name then
            Error (
                ValidationFailed
                    "Account name cannot be null or just whitespace"
            )
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxLength then
            Error (
                ValidationFailed
                    $"Account name is too long. Names must be at most \
                    %i{MaxLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    /// <summary>Trim whitespace and then validate an account name. Returns the
    /// trimmed name.</summary>
    let create (name : string) =
        name.Trim ()
        |> nonEmpty
        |> Result.bind acceptableLength
        |> Result.map AccountName

    /// <summary>The name of an account created from a statement: its number,
    /// followed by the product name in parentheses when the statement gives
    /// one, e.g. "XXXX-XXXX-XXXX-1234 (Visa Light)". Truncated to the
    /// maximum length.</summary>
    let ofNumber
        (number : AccountNumber)
        (productName : string option)
        : AccountName =
        let number = AccountNumber.value number

        let name =
            match productName |> Option.map _.Trim() with
            | Some product when product <> "" -> $"{number} ({product})"
            | _ -> number

        AccountName (name.Substring (0, min name.Length MaxLength))

    let value (AccountName name) = name

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromString name = AccountName name

/// <summary>Somewhere the user's transactions happen: chequing, savings, a
/// credit card. A source of balance sheet lines alongside items. See decision 1
/// in docs/csv-import.md.</summary>
type Account = {
    Id : Guid

    /// <summary>The number statements identify the account by. None for an
    /// account without one, which imports never match.</summary>
    Number : AccountNumber option

    Name : AccountName

    /// <summary>Which balance sheet group the account's line goes in. Its side
    /// follows the sign of its balance.</summary>
    Term : Term
}

/// <summary>A balance an account had as of a date, from a statement or entered
/// by hand. An account has at most one observation per date: a new one
/// replaces any on its date, whatever its source. See decision 3 in
/// docs/csv-import.md.</summary>
type BalanceObservation = {
    AsOf : DateOnly

    /// <summary>Signed: positive is held, negative is owed.</summary>
    Balance : Money
}

module BalanceObservation =
    /// <summary>A balance the user enters by hand, as of the instant
    /// <c>now</c>. Fails when the as-of date is in the future.</summary>
    let create
        (now : DateTimeOffset)
        (asOf : DateOnly)
        (balance : decimal)
        : Result<BalanceObservation, DomainError> =
        AsOfDate.validate now asOf
        |> Result.map (fun asOf -> {
            AsOf = asOf
            Balance = Money.create balance
        })

    /// <summary>The current balance: the observation with the latest as-of
    /// date, so an old statement never replaces a newer balance. None, an
    /// unknown balance, when the account has no observations.</summary>
    let current
        (observations : BalanceObservation list)
        : BalanceObservation option =
        match observations with
        | [] -> None
        | _ -> Some (List.maxBy _.AsOf observations)
