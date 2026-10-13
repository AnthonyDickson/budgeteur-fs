namespace Budgeteur.Tests

open System
open Expecto
open FsCheck
open FsCheck.FSharp

open Budgeteur.Domain.Account
open Budgeteur.Domain.BalanceSheet
open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.Side
open Budgeteur.Domain.Money
open Budgeteur.Domain.Term

module BalanceSheetTests =
    let private okOrFail label =
        function
        | Ok value -> value
        | Error error ->
            failtestf "%s: expected Ok, but got Error %A" label error

    let private item name side term value = {
        Id = Guid.Empty
        Name = ItemName.create name |> okOrFail "name"
        Side = side
        Term = term
        Value = Value.create value |> okOrFail "value"
        AsOf = DateOnly (2026, 1, 1)
    }

    let private sheet items : BalanceSheet = { Items = items; Accounts = [] }

    let private sampleSheet =
        sheet [
            item "Chequing" Side.Asset Term.Current 2000m
            item "Savings" Side.Asset Term.Current 5000m
            item "House" Side.Asset Term.NonCurrent 400000m
            item "Credit card" Side.Liability Term.Current 1500m
            item "Mortgage" Side.Liability Term.NonCurrent 300000m
        ]

    let private propValueAcceptedIsNonNegativeCents (amount : decimal) =
        match Value.create amount with
        | Ok balance ->
            let value = Value.value balance
            value >= 0m && value * 100m % 1m = 0m
        | Error _ -> true

    let private propValueRejectsNegatives (amount : decimal) =
        match Value.create amount with
        | Ok _ -> amount >= 0m
        | Error _ -> amount < 0m

    [<Tests>]
    let valueTests =
        testList "Value" [
            testProperty
                "Accepted values are exact, non-negative cents"
                propValueAcceptedIsNonNegativeCents
            testProperty
                "Negative amounts are always rejected"
                propValueRejectsNegatives

            testCase "create rounds to cents away from zero"
            <| fun () ->
                let balance = Value.create 13.375m |> okOrFail "balance"

                Expect.equal
                    (Value.value balance)
                    13.38m
                    "13.375 rounds up to 13.38"

            testCase "create leaves exact cents unchanged"
            <| fun () ->
                let balance = Value.create 12.50m |> okOrFail "balance"

                Expect.equal
                    (Value.value balance)
                    12.50m
                    "12.50 is already cents"

            testCase "create accepts zero"
            <| fun () ->
                let balance = Value.create 0m |> okOrFail "balance"

                Expect.equal
                    (Value.value balance)
                    0m
                    "zero is a valid magnitude"

            testCase
                "create rejects a negative magnitude with a validation error"
            <| fun () ->
                match Value.create -10m with
                | Error (Budgeteur.Shared.DomainError.ValidationFailed _) -> ()
                | other ->
                    failtestf "Expected ValidationFailed, but got %A" other
        ]

    [<Tests>]
    let balanceSheetTotalsTests =
        testList "BalanceSheet totals" [
            testCase "totalAssets sums only assets, across both terms"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.totalAssets sampleSheet)
                    407000m
                    "2000 + 5000 + 400000"

            testCase "totalLiabilities sums only liabilities, across both terms"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.totalLiabilities sampleSheet)
                    301500m
                    "1500 + 300000"

            testCase "netWorth is total assets minus total liabilities"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.netWorth sampleSheet)
                    105500m
                    "407000 - 301500"

            testCase "an empty balance sheet has zero net worth"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.netWorth (sheet []))
                    0m
                    "nothing owned or owed"

            testCase "liabilities do not contribute to total assets"
            <| fun () ->
                let liabilitiesOnly =
                    sheet [ item "Loan" Side.Liability Term.NonCurrent 500m ]

                Expect.equal
                    (BalanceSheet.totalAssets liabilitiesOnly)
                    0m
                    "a liability is never an asset"
        ]

    [<Tests>]
    let workingCapitalTests =
        testList "BalanceSheet working capital" [
            testCase "totalCurrentAssets sums only current assets"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.totalCurrentAssets sampleSheet)
                    7000m
                    "2000 + 5000, house excluded"

            testCase "totalCurrentLiabilities sums only current liabilities"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.totalCurrentLiabilities sampleSheet)
                    1500m
                    "credit card only, mortgage excluded"

            testCase
                "workingCapital is current assets minus current liabilities"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.workingCapital sampleSheet)
                    5500m
                    "7000 - 1500"

            testCase
                "workingCapital excludes non-current items, unlike net worth"
            <| fun () ->
                let nonCurrentOnly =
                    sheet [
                        item "House" Side.Asset Term.NonCurrent 400000m
                        item "Mortgage" Side.Liability Term.NonCurrent 300000m
                    ]

                Expect.equal
                    (BalanceSheet.workingCapital nonCurrentOnly)
                    0m
                    "non-current items do not count"

                Expect.equal
                    (BalanceSheet.netWorth nonCurrentOnly)
                    100000m
                    "net worth still sees them"

            testCase "an empty balance sheet has zero working capital"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.workingCapital (sheet []))
                    0m
                    "nothing current"
        ]

    [<Tests>]
    let accountLineTests =
        let account name term (balance : decimal option) = {
            Account = {
                Id = Guid.NewGuid ()
                Number = None
                Name = AccountName.create name |> okOrFail "name"
                Term = term
            }
            Current =
                balance
                |> Option.map (fun balance -> {
                    AsOf = DateOnly (2026, 3, 1)
                    Balance = Money.create balance
                })
        }

        let withAccounts accounts = { sampleSheet with Accounts = accounts }

        testList "BalanceSheet account lines" [
            testCase "an account's side follows the sign of its balance"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.accountSide (Money.create 250m))
                    (Side.Asset, 250m)
                    "a positive balance is held"

                Expect.equal
                    (BalanceSheet.accountSide (Money.create 0m))
                    (Side.Asset, 0m)
                    "a zero balance is an asset"

                Expect.equal
                    (BalanceSheet.accountSide (Money.create -250m))
                    (Side.Liability, 250m)
                    "a negative balance is owed, as a magnitude"

            testCase "accounts count towards every total by side and term"
            <| fun () ->
                let sheet =
                    withAccounts [
                        account "Everyday" Term.Current (Some 1000m)
                        account "Credit card" Term.Current (Some -400m)
                        account "Term deposit" Term.NonCurrent (Some 5000m)
                    ]

                // The sample's items: 7000 current and 400000 non-current
                // assets, 1500 current and 300000 non-current liabilities.
                Expect.equal
                    (BalanceSheet.totalCurrentAssets sheet)
                    8000m
                    "items plus the everyday account"

                Expect.equal
                    (BalanceSheet.totalCurrentLiabilities sheet)
                    1900m
                    "the overdrawn card is a current liability"

                Expect.equal
                    (BalanceSheet.totalNonCurrentAssets sheet)
                    405000m
                    "the term deposit is non-current"

                Expect.equal
                    (BalanceSheet.netWorth sheet)
                    111100m
                    "413000 - 301900"

                Expect.equal
                    (BalanceSheet.workingCapital sheet)
                    6100m
                    "8000 - 1900"

            testCase "an unknown balance is listed and left out of the totals"
            <| fun () ->
                let card = account "Credit card" Term.Current None
                let sheet = withAccounts [ card ]

                Expect.equal
                    (BalanceSheet.unknownBalances sheet)
                    [ card.Account ]
                    "the account is listed as unknown"

                Expect.equal
                    (BalanceSheet.netWorth sheet)
                    (BalanceSheet.netWorth sampleSheet)
                    "an unknown balance is not counted as zero or anything else"
        ]
