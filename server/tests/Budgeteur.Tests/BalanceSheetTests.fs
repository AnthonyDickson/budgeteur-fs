namespace Budgeteur.Tests

open System
open Expecto
open FsCheck
open FsCheck.FSharp

open Budgeteur.Domain.BalanceSheet
open Budgeteur.Domain.BalanceSheetItem

/// <summary>
/// Pure domain tests for the balance sheet item value objects and the totals derived
/// from a <c>BalanceSheet</c>. No database or HTTP is involved: these pin the
/// invariants that make an invalid item unrepresentable, plus the net worth arithmetic.
/// </summary>
module BalanceSheetTests =

    module Arbitraries =
        /// FsCheck's default string generator can produce null, but the validation
        /// functions assume a non-null input (guaranteed by JSON decoding at the edge).
        type NonNullStrings =
            static member String () : Arbitrary<string> =
                ArbMap.defaults
                |> ArbMap.arbitrary<string>
                |> Arb.filter (fun s -> not (isNull s))

    let private maxItemNameLength = 128

    let private nameConfig = {
        FsCheckConfig.defaultConfig with
            // Pushes FsCheck past the length limit so an off-by-one at the boundary
            // is exercised rather than missed.
            endSize = 512
            arbitrary = [ typeof<Arbitraries.NonNullStrings> ]
    }

    let private okOrFail label =
        function
        | Ok value -> value
        | Error error -> failtestf "%s: expected Ok, but got Error %A" label error

    let private item name kind term balance = {
        Id = Guid.Empty
        Name = ItemName.create name |> okOrFail "name"
        Kind = kind
        Term = term
        Balance = Balance.create balance |> okOrFail "balance"
    }

    let private sheet items = {
        StatementDate = DateOnly (2026, 1, 1)
        Items = items
    }

    // ItemName -----------------------------------------------------------------

    let private propNamePreservesTrim (s : string) =
        match ItemName.create s with
        | Ok trimmed -> ItemName.value trimmed = s.Trim ()
        | Error _ -> true

    let private propNameLengthBounded (s : string) =
        match ItemName.create s with
        | Ok trimmed -> (ItemName.value trimmed).Length <= maxItemNameLength
        | Error _ -> true

    let private propNameRejectsWhitespace (s : string) =
        if String.IsNullOrWhiteSpace s then
            match ItemName.create s with
            | Error _ -> true
            | Ok _ -> false
        else
            let trimmed = s.Trim ()

            match ItemName.create s with
            | Ok _ -> trimmed.Length <= maxItemNameLength
            | Error _ -> trimmed.Length > maxItemNameLength

    // Balance ------------------------------------------------------------------

    let private propBalanceAcceptedIsNonNegativeCents (amount : decimal) =
        match Balance.create amount with
        | Ok balance ->
            let value = Balance.value balance
            value >= 0m && value * 100m % 1m = 0m
        | Error _ -> true

    let private propBalanceRejectsNegatives (amount : decimal) =
        match Balance.create amount with
        | Ok _ -> amount >= 0m
        | Error _ -> amount < 0m

    // BalanceSheet -------------------------------------------------------------

    let private sampleSheet =
        sheet [
            item "Chequing" ItemKind.Asset Term.Current 2000m
            item "Savings" ItemKind.Asset Term.Current 5000m
            item "House" ItemKind.Asset Term.NonCurrent 400000m
            item "Credit card" ItemKind.Liability Term.Current 1500m
            item "Mortgage" ItemKind.Liability Term.NonCurrent 300000m
        ]

    [<Tests>]
    let itemNameTests =
        testList "ItemName" [
            testPropertyWithConfig
                nameConfig
                "Acceptance preserves trim: Ok trimmed exactly equals s.Trim()"
                propNamePreservesTrim

            testPropertyWithConfig
                nameConfig
                "Length bounded on accept: accepted name length <= 128"
                propNameLengthBounded

            testPropertyWithConfig
                nameConfig
                "Whitespace rejection: Error iff trimmed input is empty"
                propNameRejectsWhitespace

            testCase "create accepts a name at exactly the length limit"
            <| fun () ->
                let name = String ('a', maxItemNameLength)
                Expect.isOk (ItemName.create name) "128 character names are allowed"

            testCase "create rejects a name one character over the limit"
            <| fun () ->
                let name = String ('a', maxItemNameLength + 1)
                Expect.isError (ItemName.create name) "129 character names are rejected"
        ]

    [<Tests>]
    let balanceTests =
        testList "Balance" [
            testProperty "Accepted balances are exact, non-negative cents" propBalanceAcceptedIsNonNegativeCents
            testProperty "Negative amounts are always rejected" propBalanceRejectsNegatives

            testCase "create rounds to cents away from zero"
            <| fun () ->
                let balance = Balance.create 13.375m |> okOrFail "balance"
                Expect.equal (Balance.value balance) 13.38m "13.375 rounds up to 13.38"

            testCase "create leaves exact cents unchanged"
            <| fun () ->
                let balance = Balance.create 12.50m |> okOrFail "balance"
                Expect.equal (Balance.value balance) 12.50m "12.50 is already cents"

            testCase "create accepts zero"
            <| fun () ->
                let balance = Balance.create 0m |> okOrFail "balance"
                Expect.equal (Balance.value balance) 0m "zero is a valid magnitude"

            testCase "create rejects a negative magnitude with a validation error"
            <| fun () ->
                match Balance.create -10m with
                | Error (Budgeteur.Shared.DomainError.ValidationFailed _) -> ()
                | other -> failtestf "Expected ValidationFailed, but got %A" other
        ]

    [<Tests>]
    let balanceSheetTotalsTests =
        testList "BalanceSheet totals" [
            testCase "totalAssets sums only assets, across both terms"
            <| fun () -> Expect.equal (BalanceSheet.totalAssets sampleSheet) 407000m "2000 + 5000 + 400000"

            testCase "totalLiabilities sums only liabilities, across both terms"
            <| fun () -> Expect.equal (BalanceSheet.totalLiabilities sampleSheet) 301500m "1500 + 300000"

            testCase "netWorth is total assets minus total liabilities"
            <| fun () -> Expect.equal (BalanceSheet.netWorth sampleSheet) 105500m "407000 - 301500"

            testCase "an empty balance sheet has zero net worth"
            <| fun () -> Expect.equal (BalanceSheet.netWorth (sheet [])) 0m "nothing owned or owed"

            testCase "liabilities do not contribute to total assets"
            <| fun () ->
                let liabilitiesOnly = sheet [ item "Loan" ItemKind.Liability Term.NonCurrent 500m ]
                Expect.equal (BalanceSheet.totalAssets liabilitiesOnly) 0m "a liability is never an asset"
        ]

    [<Tests>]
    let workingCapitalTests =
        testList "BalanceSheet working capital" [
            testCase "totalCurrentAssets sums only current assets"
            <| fun () -> Expect.equal (BalanceSheet.totalCurrentAssets sampleSheet) 7000m "2000 + 5000, house excluded"

            testCase "totalCurrentLiabilities sums only current liabilities"
            <| fun () ->
                Expect.equal
                    (BalanceSheet.totalCurrentLiabilities sampleSheet)
                    1500m
                    "credit card only, mortgage excluded"

            testCase "workingCapital is current assets minus current liabilities"
            <| fun () -> Expect.equal (BalanceSheet.workingCapital sampleSheet) 5500m "7000 - 1500"

            testCase "workingCapital excludes non-current items, unlike net worth"
            <| fun () ->
                let nonCurrentOnly =
                    sheet [
                        item "House" ItemKind.Asset Term.NonCurrent 400000m
                        item "Mortgage" ItemKind.Liability Term.NonCurrent 300000m
                    ]

                Expect.equal (BalanceSheet.workingCapital nonCurrentOnly) 0m "non-current items do not count"
                Expect.equal (BalanceSheet.netWorth nonCurrentOnly) 100000m "net worth still sees them"

            testCase "an empty balance sheet has zero working capital"
            <| fun () -> Expect.equal (BalanceSheet.workingCapital (sheet [])) 0m "nothing current"
        ]
