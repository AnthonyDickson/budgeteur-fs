namespace Budgeteur.Feature.Import

open System
open System.Globalization

open Budgeteur.Domain.Account
open Budgeteur.Domain.Money
open Budgeteur.Domain.Transaction

/// <summary>The balance a row's running-balance column reports: the account's
/// balance once the row is applied, and the date it is accurate as of, which
/// may differ from the transaction date.</summary>
type BalanceAfter = { Date : DateOnly; Balance : Money }

/// <summary>A statement row read into domain types.</summary>
type StatementRow = {
    /// <summary>The row's line number in the file.</summary>
    Line : int
    Date : DateOnly
    Description : TransactionDescription
    /// <summary>Signed as the app stores it: money in is positive.</summary>
    Amount : Money
    /// <summary>When the format has a running balance.</summary>
    Balance : BalanceAfter option
    /// <summary>When the row names the other party's account and it is an
    /// account number.</summary>
    OtherPartyAccount : AccountNumber option
    /// <summary>Recognises the row in a later import. See decision 6 in
    /// docs/csv-import.md.</summary>
    ImportHash : string
}

/// <summary>One CSV file read into domain types: the transactions of one
/// account, and its daily closing balances when the statement has
/// them.</summary>
type Statement = {
    FileName : string
    /// <summary>The name of the format the file was read with.</summary>
    Format : string
    Account : StatementAccount
    Rows : StatementRow list
    /// <summary>One per balance date: the balance after the date's last row,
    /// by the format's row order. See decision 3 in
    /// docs/csv-import.md.</summary>
    Observations : BalanceObservation list
}

/// <summary>Why a file, or a row in it, cannot be imported.</summary>
type ImportError = {
    FileName : string
    /// <summary>None for a problem with the file as a whole.</summary>
    Line : int option
    Message : string
}

module ImportError =
    let describe (error : ImportError) =
        match error.Line with
        | Some line -> $"{error.FileName} line {line}: {error.Message}"
        | None -> $"{error.FileName}: {error.Message}"

/// <summary>The interpreter for formats: detection, then reading each row.
/// This is the adapter between the banks' exports and the domain. See
/// decisions 5 and 7 in docs/csv-import.md.</summary>
module Statement =
    open FsToolkit.ErrorHandling

    /// <summary>A file that matched a format: the account its preamble names,
    /// if it has one, and the lines after the header.</summary>
    type private Detected = {
        Format : Format
        Account : StatementAccount option
        Rows : CsvLine list
    }

    /// <summary>The file in the format, when its header is one of the file's
    /// lines, with no lines before it for a format without a preamble, or
    /// lines the preamble function reads. Error None when the header is
    /// missing; Error (Some reason) when the preamble does not fit.</summary>
    let private detectAs
        (lines : CsvLine list)
        (format : Format)
        : Result<Detected, string option> =
        match
            List.tryFindIndex (fun line -> line.Text = format.Header) lines
        with
        | None -> Error None
        | Some index ->
            let rows = List.skip (index + 1) lines

            match format.Account with
            | AccountColumn _ when index = 0 ->
                Ok {
                    Format = format
                    Account = None
                    Rows = rows
                }
            | AccountColumn _ ->
                Error (
                    Some $"the {format.Name} header is not on the first line"
                )
            | Preamble read ->
                lines
                |> List.take index
                |> List.map _.Text
                |> read
                |> Result.map (fun account -> {
                    Format = format
                    Account = Some account
                    Rows = rows
                })
                |> Result.mapError (fun reason ->
                    Some $"{reason} for the {format.Name} format")

    /// <summary>The message for a file that matches no format: the start of
    /// the file and each format's header, to compare by eye.</summary>
    let private noFormat
        (formats : Format list)
        (lines : CsvLine list)
        (reasons : string list)
        =
        // Continuation lines are indented, so a reader of the joined errors of
        // several files can tell where this one ends.
        let indent (text : string) = "    " + text

        [
            yield "matches no known format."
            yield!
                reasons
                |> List.map (fun reason -> $"  It looks close, but {reason}.")
            yield "  The file starts with:"
            yield! lines |> List.truncate 3 |> List.map (_.Text >> indent)
            yield "  Expected one of these headers:"
            yield!
                formats
                |> List.map (fun format ->
                    indent $"{format.Name}: {format.Header}")
        ]
        |> String.concat "\n"

    let private detect (formats : Format list) (lines : CsvLine list) =
        let results = formats |> List.map (detectAs lines)

        match results |> List.tryPick Result.toOption with
        | Some detected -> Ok detected
        | None ->
            let reasons =
                results
                |> List.choose (function
                    | Error reason -> reason
                    | Ok _ -> None)

            Error (noFormat formats lines reasons)

    /// <summary>A row read into domain types, with the statement's account
    /// number as the row names it or the preamble does.</summary>
    type private ReadRow = {
        Row : StatementRow
        AccountNumber : AccountNumber
    }

    let private validationMessage error =
        match error with
        | Budgeteur.Shared.DomainError.ValidationFailed message -> message
        | other -> string other

    /// <summary>A sign and a decimal point, but no thousands separators or
    /// exponents, which no statement uses.</summary>
    let private amountStyles =
        NumberStyles.AllowLeadingSign ||| NumberStyles.AllowDecimalPoint

    /// <summary>An amount in the import hash's canonical form, e.g. -8.50,
    /// however the statement wrote it.</summary>
    let private canonical (money : Money) =
        (Money.value money).ToString("0.00", CultureInfo.InvariantCulture)

    let private parseDecimal (text : string) =
        match
            Decimal.TryParse (text, amountStyles, CultureInfo.InvariantCulture)
        with
        | true, value -> Some value
        | false, _ -> None

    /// <summary>Read one row's fields by the format. Every field that fails is
    /// reported. <c>statementNumber</c> is the account number the preamble
    /// names, if the format has one.</summary>
    let private readRow
        (format : Format)
        (statementNumber : AccountNumber option)
        (header : string list)
        (line : CsvLine)
        : Result<ReadRow, string list> =
        result {
            let! fields = Csv.fields line.Text |> Result.mapError List.singleton

            do!
                if List.length fields = List.length header then
                    Ok ()
                else
                    Error [
                        $"expected {List.length header} fields like the \
                        header, but found {List.length fields}"
                    ]

            let values = List.zip header fields |> Map.ofList

            let text column =
                match Map.tryFind column values with
                | Some value -> Ok (value.Trim ())
                | None -> Error $"the format has no column \"{column}\""

            let date column =
                text column
                |> Result.bind (fun value ->
                    DateFormat.parse format.DateFormat value
                    |> Result.requireSome
                        $"{column} \"{value}\" is not a date like \
                        {DateFormat.pattern format.DateFormat}")

            let money column =
                text column
                |> Result.bind (fun value ->
                    parseDecimal value
                    |> Option.map Money.create
                    |> Result.requireSome
                        $"{column} \"{value}\" is not an amount")

            let description =
                format.Description
                |> List.traverseResultM text
                |> Result.bind (fun parts ->
                    match
                        parts |> List.filter ((<>) "") |> String.concat " "
                    with
                    | "" -> text format.TransactionType
                    | joined -> Ok joined)
                |> Result.bind (fun description ->
                    description.Substring (
                        0,
                        min description.Length TransactionDescription.MaxLength
                    )
                    |> TransactionDescription.create
                    |> Result.mapError (fun _ -> "the row has no description"))

            let amount =
                money format.Amount
                |> Result.map (fun amount ->
                    match format.Sign with
                    | AsGiven -> amount
                    | Negated -> Money.create -(Money.value amount))

            let balance =
                match format.Balance with
                | None -> Ok None
                | Some balance ->
                    Result.map2
                        (fun date balance ->
                            Some { Date = date; Balance = balance })
                        (date balance.DateColumn)
                        (money balance.Column)

            let accountNumber =
                match format.Account, statementNumber with
                | AccountColumn column, _ ->
                    text column
                    |> Result.bind (
                        AccountNumber.create
                        >> Result.mapError validationMessage
                    )
                | Preamble _, Some number -> Ok number
                | Preamble _, None -> Error "the preamble names no account"

            // Another party's account may be anything the bank recorded, so
            // a value that is not an account number is no account.
            let otherPartyAccount =
                match format.OtherPartyAccount with
                | None -> Ok None
                | Some column ->
                    text column
                    |> Result.map (AccountNumber.create >> Result.toOption)

            let! (transactionDate,
                  description,
                  amount,
                  balance,
                  accountNumber,
                  otherPartyAccount) =
                validation {
                    let! transactionDate = date format.Date
                    and! description = description
                    and! amount = amount
                    and! balance = balance
                    and! accountNumber = accountNumber
                    and! otherPartyAccount = otherPartyAccount

                    return
                        transactionDate,
                        description,
                        amount,
                        balance,
                        accountNumber,
                        otherPartyAccount
                }

            let! identity =
                format.Identity
                |> List.traverseResultM (fun field ->
                    match field with
                    | Column column -> text column
                    | DateColumn column ->
                        date column
                        |> Result.map (fun date -> date.ToString "O")
                    | Amount -> Ok (canonical amount)
                    | RunningBalance ->
                        balance
                        |> Option.map (fun after -> canonical after.Balance)
                        |> Result.requireSome
                            "the format identifies rows by a running balance \
                            it does not have")
                |> Result.mapError List.singleton

            return {
                Row = {
                    Line = line.Number
                    Date = transactionDate
                    Description = description
                    Amount = amount
                    Balance = balance
                    OtherPartyAccount = otherPartyAccount
                    ImportHash = ImportHash.compute accountNumber identity
                }
                AccountNumber = accountNumber
            }
        }

    /// <summary>The statement's account: the preamble's, or the account column
    /// of the first row, which every other row must repeat, since one statement
    /// holds one account.</summary>
    let private account (detected : Detected) (rows : ReadRow list) =
        match detected.Account, rows with
        | Some account, _ -> Ok account
        | None, [] ->
            Error [ None, "has no transactions, so its account is unknown" ]
        | None, first :: _ ->
            match
                rows
                |> List.filter (fun row ->
                    row.AccountNumber <> first.AccountNumber)
            with
            | [] ->
                Ok {
                    Number = first.AccountNumber
                    ProductName = None
                }
            | others ->
                others
                |> List.map (fun row ->
                    Some row.Row.Line,
                    "the account number differs from the first row's, but a \
                    statement holds one account")
                |> Error

    /// <summary>The closing balance of each date, after checking the balance
    /// dates run in the format's row order.</summary>
    let private observations (format : Format) (rows : StatementRow list) =
        match format.Balance with
        | None -> Ok []
        | Some balance ->
            let dated =
                rows
                |> List.choose (fun row ->
                    row.Balance |> Option.map (fun after -> row.Line, after))

            let outOfOrder =
                dated
                |> List.pairwise
                |> List.filter (fun ((_, previous), (_, next)) ->
                    match balance.Order with
                    | OldestFirst -> next.Date < previous.Date
                    | NewestFirst -> next.Date > previous.Date)

            match outOfOrder, balance.Order with
            | [], OldestFirst
            | [], NewestFirst ->
                let inOrder =
                    match balance.Order with
                    | OldestFirst -> dated
                    | NewestFirst -> List.rev dated

                // A later row on a date replaces the earlier one's balance.
                inOrder
                |> List.fold
                    (fun closing (_, after) ->
                        Map.add after.Date after.Balance closing)
                    Map.empty
                |> Map.toList
                |> List.map (fun (date, balance) -> {
                    AsOf = date
                    Balance = balance
                })
                |> Ok
            | ((_, previous), (line, next)) :: _, order ->
                let listed =
                    match order with
                    | OldestFirst -> "oldest first"
                    | NewestFirst -> "newest first"

                Error [
                    Some line,
                    $"""the {balance.DateColumn} {next.Date.ToString "O"} \
                    is out of order after {previous.Date.ToString "O"}: \
                    {format.Name} statements list rows {listed}"""
                ]

    /// <summary>Read a file with the first format it matches. Fails with
    /// every problem found: no matching format, or each row that cannot be
    /// read.</summary>
    let parse
        (formats : Format list)
        (fileName : string)
        (text : string)
        : Result<Statement, ImportError list> =
        let error (line, message) = {
            FileName = fileName
            Line = line
            Message = message
        }

        result {
            let lines = Csv.lines text

            let! detected =
                detect formats lines
                |> Result.mapError (fun message -> [ error (None, message) ])

            let header =
                Csv.fields detected.Format.Header |> Result.defaultValue []

            let! rows =
                detected.Rows
                |> List.map (fun line ->
                    readRow
                        detected.Format
                        (detected.Account |> Option.map _.Number)
                        header
                        line
                    |> Result.mapError (
                        List.map (fun message ->
                            error (Some line.Number, message))
                    ))
                |> List.sequenceResultA
                |> Result.mapError List.concat

            let! account =
                account detected rows |> Result.mapError (List.map error)

            let rows = rows |> List.map _.Row

            let! observations =
                observations detected.Format rows
                |> Result.mapError (List.map error)

            return {
                FileName = fileName
                Format = detected.Format.Name
                Account = account
                Rows = rows
                Observations = observations
            }
        }

    /// <summary>Read every file, failing with the problems of all of
    /// them.</summary>
    let parseAll
        (formats : Format list)
        (files : (string * string) list)
        : Result<Statement list, ImportError list> =
        files
        |> List.map (fun (fileName, text) -> parse formats fileName text)
        |> List.sequenceResultA
        |> Result.mapError List.concat
