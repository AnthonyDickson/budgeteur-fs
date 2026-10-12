namespace Budgeteur.Feature.Import

open System
open System.Globalization
open System.Text.RegularExpressions

open Budgeteur.Domain.Account

/// <summary>The date formats statements use, each parsed exactly and
/// independent of culture.</summary>
type DateFormat =
    /// <summary>yyyy-MM-dd</summary>
    | IsoDate
    /// <summary>yyyy/MM/dd</summary>
    | SlashedDate

module DateFormat =
    let pattern format =
        match format with
        | IsoDate -> "yyyy-MM-dd"
        | SlashedDate -> "yyyy/MM/dd"

    let parse (format : DateFormat) (text : string) : DateOnly option =
        match
            DateOnly.TryParseExact (
                text,
                pattern format,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None
            )
        with
        | true, date -> Some date
        | false, _ -> None

/// <summary>How a statement signs its amounts.</summary>
type Sign =
    /// <summary>Money in is positive, as the app stores it.</summary>
    | AsGiven
    /// <summary>Money out is positive, as on a credit card statement.</summary>
    | Negated

/// <summary>The order a statement lists its rows in.</summary>
type RowOrder =
    | OldestFirst
    | NewestFirst

/// <summary>A statement's running balance: the account's balance after each
/// row, and the date the balance changed on.</summary>
type RunningBalance = {
    Column : string
    DateColumn : string
    /// <summary>Decides which row closes each date. A file whose balance dates
    /// run the other way is rejected.</summary>
    Order : RowOrder
}

/// <summary>The account a statement belongs to, as the statement names
/// it.</summary>
type StatementAccount = {
    Number : AccountNumber
    /// <summary>The bank's name for the product, e.g. "Visa Light", when the
    /// statement gives one.</summary>
    ProductName : string option
}

/// <summary>Where a format finds the statement's account number.</summary>
type AccountSource =
    /// <summary>A column on every row.</summary>
    | AccountColumn of string
    /// <summary>The lines before the header, read by a function that fails
    /// with a reason when they are not the format's preamble.</summary>
    | Preamble of (string list -> Result<StatementAccount, string>)

/// <summary>A field of a row that identifies the transaction across exports,
/// for the import hash. See decision 6 in docs/csv-import.md.</summary>
type IdentityField =
    /// <summary>A column's text, trimmed.</summary>
    | Column of string
    /// <summary>A date column, in ISO form.</summary>
    | DateColumn of string
    /// <summary>The signed amount, with two decimal places.</summary>
    | Amount
    /// <summary>The running balance, with two decimal places.</summary>
    | RunningBalance

/// <summary>How to read one bank's CSV export, held as data and read by one
/// interpreter. Fields name their columns by header name, and the header must
/// match exactly, so any change to the columns fails detection instead of
/// reading the wrong field. See decision 5 in docs/csv-import.md.</summary>
type Format = {
    Name : string
    /// <summary>The exact header line.</summary>
    Header : string
    Account : AccountSource
    /// <summary>The date the transaction happened, not when it was
    /// processed.</summary>
    Date : string
    DateFormat : DateFormat
    /// <summary>Joined with a space, skipping empty ones.</summary>
    Description : string list
    /// <summary>The description when the description columns are
    /// empty.</summary>
    TransactionType : string
    Amount : string
    Sign : Sign
    Balance : RunningBalance option
    /// <summary>The other party's account number, for transfer
    /// detection.</summary>
    OtherPartyAccount : string option
    /// <summary>Chosen deliberately per format: a hash over fields that change
    /// when the export changes makes every overlapping row look new.</summary>
    Identity : IdentityField list
}

/// <summary>The built-in formats.</summary>
module Formats =
    let kiwibank = {
        Name = "Kiwibank"
        Header =
            "Account number,Effective Date,Transaction Date,Description,\
            Transaction Code,Particulars,Code,Reference,Other Party Name,\
            Other Party Account Number,Other Party Particulars,\
            Other Party Code,Other Party Reference,Amount,Balance"
        Account = AccountColumn "Account number"
        Date = "Effective Date"
        DateFormat = IsoDate
        Description = [ "Description" ]
        TransactionType = "Transaction Code"
        Amount = "Amount"
        Sign = AsGiven
        Balance =
            Some {
                Column = "Balance"
                DateColumn = "Transaction Date"
                Order = OldestFirst
            }
        OtherPartyAccount = Some "Other Party Account Number"
        // The running balance tells apart two identical purchases on one day,
        // and the transaction date is the one the balance changes on, so both
        // come from the same ledger entry.
        Identity = [ DateColumn "Transaction Date"; Amount; RunningBalance ]
    }

    /// <summary>The line naming the card, e.g. "Card Number
    /// XXXX-XXXX-XXXX-1234 (Visa Light)".</summary>
    let private cardLine =
        Regex (
            @"^Card Number (\S+)(?: \((.+)\))?$",
            RegexOptions.CultureInvariant
        )

    /// <summary>ASB card statements start with when they were created, the
    /// card, and the date range.</summary>
    let private asbCardPreamble (lines : string list) =
        match
            lines
            |> List.map (fun line -> cardLine.Match (line.Trim ()))
            |> List.tryFind _.Success
        with
        | None -> Error "the lines before the header name no card number"
        | Some card ->
            AccountNumber.create card.Groups[1].Value
            |> Result.mapError (fun _ ->
                $"\"{card.Groups[1].Value}\" is not a card number")
            |> Result.map (fun number -> {
                Number = number
                ProductName =
                    if card.Groups[2].Success then
                        Some card.Groups[2].Value
                    else
                        None
            })

    let asbCard = {
        Name = "ASB card"
        Header =
            "Date Processed,Date of Transaction,Unique Id,Tran Type,Reference,\
            Description,Amount"
        Account = Preamble asbCardPreamble
        Date = "Date of Transaction"
        DateFormat = SlashedDate
        Description = [ "Description" ]
        TransactionType = "Tran Type"
        Amount = "Amount"
        Sign = Negated
        Balance = None
        OtherPartyAccount = None
        // A date and a sequence number per card.
        Identity = [ Column "Unique Id" ]
    }

    let all = [ kiwibank; asbCard ]
