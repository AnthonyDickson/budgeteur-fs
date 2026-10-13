namespace Budgeteur.Tests.Import

/// The anonymised bank exports in Import/Fixtures, copied next to the tests.
module Fixture =
    open System
    open System.IO

    let read (name : string) =
        File.ReadAllText (
            Path.Combine (AppContext.BaseDirectory, "Import", "Fixtures", name)
        )

module StatementTests =
    open System
    open Expecto

    open Budgeteur.Domain.Account
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Import

    let private parse fileName text =
        Statement.parse Formats.all fileName text

    let private parseOk fileName text =
        match parse fileName text with
        | Ok statement -> statement
        | Error errors ->
            failtestf
                "expected %s to parse, but got:\n%s"
                fileName
                (errors |> List.map ImportError.describe |> String.concat "\n")

    let private parseErrors fileName text =
        match parse fileName text with
        | Ok _ -> failtestf "expected %s to fail" fileName
        | Error errors -> errors

    let private number text =
        AccountNumber.create text |> Result.defaultWith (failtestf "%A")

    let private first list =
        match list with
        | head :: _ -> head
        | [] -> failtest "expected a non-empty list"

    let private last list = first (List.rev list)

    let private description (row : StatementRow) =
        TransactionDescription.value row.Description

    let private kiwibankHeader = Formats.kiwibank.Header

    /// A Kiwibank row with only the fields the format reads filled in.
    let private kiwibankRow
        (date : string)
        (description : string)
        (amount : string)
        (balance : string)
        =
        $"12-3456-0789012-00,{date},{date},{description},EFTPOS PURCHASE,\
        ,,,,,,,,{amount},{balance}"

    [<Tests>]
    let fixtureTests =
        testList "Statement fixtures" [
            testCase "Kiwibank chequing reads every row"
            <| fun () ->
                let statement =
                    parseOk
                        "KiwibankChequing.csv"
                        (Fixture.read "KiwibankChequing.csv")

                Expect.equal
                    statement.Format
                    "Kiwibank"
                    "the format is detected"

                Expect.equal
                    statement.Account
                    {
                        Number = number "12-3456-0789012-000"
                        ProductName = None
                    }
                    "the account comes from the account number column"

                Expect.equal
                    (List.length statement.Rows)
                    192
                    "every row is read"

                let firstRow = first statement.Rows
                Expect.equal firstRow.Line 2 "rows keep their line numbers"

                Expect.equal
                    firstRow.Date
                    (DateOnly (2026, 3, 27))
                    "the date is the effective date, not the processing date"

                Expect.equal
                    (description firstRow)
                    "HARBOUR CAFE AUCKLAND"
                    "description"

                Expect.equal
                    firstRow.Amount
                    (Money.create -8.50m)
                    "amounts are as given"

            testCase "Kiwibank records one observation per processing date"
            <| fun () ->
                let statement =
                    parseOk
                        "KiwibankChequing.csv"
                        (Fixture.read "KiwibankChequing.csv")

                Expect.equal
                    (List.length statement.Observations)
                    79
                    "one per distinct transaction date"

                // Three rows were processed on 28 March; the last one closes
                // the day.
                Expect.equal
                    (first statement.Observations)
                    {
                        AsOf = DateOnly (2026, 3, 28)
                        Balance = Money.create 899.91m
                    }
                    "the first date closes with its last row's balance"

                Expect.equal
                    (last statement.Observations)
                    {
                        AsOf = DateOnly (2026, 6, 26)
                        Balance = Money.create 1053.99m
                    }
                    "the statement's closing balance"

            testCase "Kiwibank savings names chequing as the other party"
            <| fun () ->
                let statement =
                    parseOk
                        "KiwibankSavings.csv"
                        (Fixture.read "KiwibankSavings.csv")

                Expect.equal
                    statement.Account.Number
                    (number "12-3456-0789012-001")
                    "a two-digit suffix is read in canonical form"

                let transfers =
                    statement.Rows
                    |> List.filter (fun row ->
                        row.OtherPartyAccount =
                            Some (number "12-3456-0789012-000"))

                Expect.equal
                    (List.length transfers)
                    20
                    "the transfers to chequing"

                Expect.isTrue
                    (statement.Rows
                     |> List.exists (fun row -> row.OtherPartyAccount = None))
                    "rows without another party's account have none"

            testCase "ASB card reads the preamble and negates amounts"
            <| fun () ->
                let statement =
                    parseOk "AsbCard.csv" (Fixture.read "AsbCard.csv")

                Expect.equal
                    statement.Format
                    "ASB card"
                    "the format is detected"

                Expect.equal
                    statement.Account
                    {
                        Number = number "XXXX-XXXX-XXXX-0000"
                        ProductName = Some "Visa Light"
                    }
                    "the card and product come from the preamble"

                Expect.equal (List.length statement.Rows) 8 "every row is read"

                let firstRow = first statement.Rows

                Expect.equal
                    firstRow.Date
                    (DateOnly (2026, 6, 16))
                    "the date is the transaction date, not the processed date"

                Expect.equal
                    firstRow.Amount
                    (Money.create -707.00m)
                    "a purchase is money out"

                Expect.equal
                    (description firstRow)
                    "CITY COMPUTERS AUCKLAND"
                    "quotes are removed"

                let payment =
                    statement.Rows
                    |> List.filter (fun row ->
                        description row = "PAYMENT RECEIVED THANK YOU")
                    |> first

                Expect.equal
                    payment.Amount
                    (Money.create 727.00m)
                    "a payment is money in"

                Expect.isEmpty
                    statement.Observations
                    "ASB cards have no balance"
        ]

    [<Tests>]
    let detectionTests =
        testList "Statement detection" [
            testCase "a file with no known header lists the headers to compare"
            <| fun () ->
                let errors =
                    parseErrors
                        "export.csv"
                        "Date,Payee,Amount\n2026-03-01,Cafe,-4.50\n"

                match errors with
                | [ error ] ->
                    Expect.equal error.FileName "export.csv" "the file is named"
                    Expect.isNone error.Line "the whole file is rejected"

                    Expect.stringContains
                        error.Message
                        "Date,Payee,Amount"
                        "the file's start"

                    Expect.stringContains
                        error.Message
                        kiwibankHeader
                        "the Kiwibank header"

                    Expect.stringContains
                        error.Message
                        Formats.asbCard.Header
                        "the ASB card header"
                | errors -> failtestf "expected one error, got %A" errors

            testCase "a header with a changed column is not detected"
            <| fun () ->
                let header =
                    kiwibankHeader.Replace (",Balance", ",Running Balance")

                parseErrors
                    "changed.csv"
                    (header
                     + "\n"
                     + kiwibankRow "2026-03-01" "Cafe" "-4.50" "10.00")
                |> ignore

            testCase "a format without a preamble needs its header first"
            <| fun () ->
                let text =
                    "Exported 2026-03-01\n"
                    + kiwibankHeader
                    + "\n"
                    + kiwibankRow "2026-03-01" "Cafe" "-4.50" "10.00"

                let errors = parseErrors "kiwibank.csv" text

                Expect.stringContains
                    (first errors).Message
                    "not on the first line"
                    "the near miss is explained"

            testCase "an ASB card file without its card line is rejected"
            <| fun () ->
                let text =
                    "Created date / time : 27 June 2026 / 10:25:49\n"
                    + Formats.asbCard.Header
                    + "\n2026/06/17,2026/06/16,2026061701,DEBIT,0000,"
                    + "\"Cafe\",4.50\n"

                let errors = parseErrors "card.csv" text

                Expect.stringContains
                    (first errors).Message
                    "no card number"
                    "the preamble's reason is given"
        ]

    [<Tests>]
    let rowTests =
        testList "Statement rows" [
            testCase "every failing row is reported with its line"
            <| fun () ->
                let text =
                    String.concat "\n" [
                        kiwibankHeader
                        kiwibankRow "2026-03-01" "Cafe" "-4.50" "10.00"
                        kiwibankRow "01/03/2026" "Cafe" "-4.50" "5.50"
                        ""
                        kiwibankRow "2026-03-02" "Cafe" "four" "5.50"
                    ]

                let errors = parseErrors "bad.csv" text

                Expect.equal
                    (errors |> List.map (fun error -> error.Line))
                    [ Some 3; Some 3; Some 5 ]
                    "both bad dates on line 3 and the bad amount on line 5"

                Expect.stringContains
                    (ImportError.describe (last errors))
                    "bad.csv line 5: Amount \"four\" is not an amount"
                    "the file, line, column, and value are named"

            testCase "a row with the wrong number of fields is reported"
            <| fun () ->
                let errors =
                    parseErrors
                        "short.csv"
                        (kiwibankHeader + "\n12-3456-0789012-00,2026-03-01")

                Expect.stringContains
                    (first errors).Message
                    "expected 15 fields"
                    "the field count is checked"

            testCase "balance dates out of the declared order are rejected"
            <| fun () ->
                let text =
                    String.concat "\n" [
                        kiwibankHeader
                        kiwibankRow "2026-03-02" "Cafe" "-4.50" "10.00"
                        kiwibankRow "2026-03-01" "Cafe" "-4.50" "5.50"
                    ]

                let errors = parseErrors "newest-first.csv" text

                Expect.equal
                    (first errors).Line
                    (Some 3)
                    "the first row out of order"

                Expect.stringContains
                    (first errors).Message
                    "oldest first"
                    "the declared order is named"

            testCase "every row must name the same account"
            <| fun () ->
                let text =
                    String.concat "\n" [
                        kiwibankHeader
                        kiwibankRow "2026-03-01" "Cafe" "-4.50" "10.00"
                        (kiwibankRow "2026-03-01" "Cafe" "-4.50" "5.50")
                            .Replace("-00,", "-01,")
                    ]

                let errors = parseErrors "two-accounts.csv" text

                Expect.equal
                    (first errors).Line
                    (Some 3)
                    "the row with the other account"

            testCase "descriptions handle quotes, length, and other scripts"
            <| fun () ->
                let long = String ('x', 300)

                let text =
                    String.concat "\r\n" [
                        kiwibankHeader
                        kiwibankRow
                            "2026-03-01"
                            "\"Cafe, \"\"The Bean\"\"\""
                            "-4.50"
                            "10.00"
                        kiwibankRow "2026-03-01" long "-1.00" "9.00"
                        kiwibankRow "2026-03-01" "Kai Māori café" "-1.00" "8.00"
                        // An empty description falls back to the transaction
                        // type.
                        kiwibankRow "2026-03-01" "" "-1.00" "7.00"
                    ]

                let statement = parseOk "edge.csv" text

                Expect.equal
                    (statement.Rows |> List.map description)
                    [
                        "Cafe, \"The Bean\""
                        String ('x', TransactionDescription.MaxLength)
                        "Kai Māori café"
                        "EFTPOS PURCHASE"
                    ]
                    "quoted, truncated, kept, and the fallback"
        ]
