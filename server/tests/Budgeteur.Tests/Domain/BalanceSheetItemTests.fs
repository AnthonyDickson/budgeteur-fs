namespace Budgeteur.Tests

open System
open Expecto
open FsCheck
open FsCheck.FSharp

open Budgeteur.Domain.BalanceSheet
open Budgeteur.Domain.BalanceSheetItem

module BalanceSheetItemTests =
    module Arbitraries =
        /// FsCheck's default string generator can produce null, but the validation
        /// functions assume a non-null input (guaranteed by JSON decoding at the edge).
        type NonNullStrings =
            static member String () : Arbitrary<string> =
                ArbMap.defaults
                |> ArbMap.arbitrary<string>
                |> Arb.filter (fun s -> not (isNull s))

    let private propNamePreservesTrim (s : string) =
        match ItemName.create s with
        | Ok trimmed -> ItemName.value trimmed = s.Trim ()
        | Error _ -> true

    let private propNameLengthBounded (s : string) =
        match ItemName.create s with
        | Ok trimmed -> (ItemName.value trimmed).Length <= ItemName.MaxLength
        | Error _ -> true

    let private propNameRejectsWhitespace (s : string) =
        if String.IsNullOrWhiteSpace s then
            match ItemName.create s with
            | Error _ -> true
            | Ok _ -> false
        else
            let trimmed = s.Trim ()

            match ItemName.create s with
            | Ok _ -> trimmed.Length <= ItemName.MaxLength
            | Error _ -> trimmed.Length > ItemName.MaxLength

    let private nameConfig = {
        FsCheckConfig.defaultConfig with
            // Pushes FsCheck past the length limit so an off-by-one at the boundary
            // is exercised rather than missed.
            endSize = 512
            arbitrary = [ typeof<Arbitraries.NonNullStrings> ]
    }

    [<Tests>]
    let itemNameTests =
        testList "ItemName" [
            testPropertyWithConfig
                nameConfig
                "Acceptance preserves trim: Ok trimmed exactly equals s.Trim()"
                propNamePreservesTrim

            testPropertyWithConfig
                nameConfig
                $"Length bounded on accept: accepted name length <= {ItemName.MaxLength}"
                propNameLengthBounded

            testPropertyWithConfig
                nameConfig
                "Whitespace rejection: Error iff trimmed input is empty"
                propNameRejectsWhitespace

            testCase "create accepts a name at exactly the length limit"
            <| fun () ->
                let name = String ('a', ItemName.MaxLength)
                Expect.isOk (ItemName.create name) $"{ItemName.MaxLength} character names are allowed"

            testCase "create rejects a name one character over the limit"
            <| fun () ->
                let name = String ('a', ItemName.MaxLength + 1)
                Expect.isError (ItemName.create name) $"{ItemName.MaxLength + 1} character names are rejected"
        ]

    [<Tests>]
    let itemKindTests =
        testList "ItemKind" [
            testCase "Asset round trip"
            <| fun () ->
                Expect.equal
                    (Ok ItemKind.Asset)
                    (ItemKind.Asset |> ItemKind.toString |> ItemKind.parse)
                    "Could not round trip Asset"

            testCase "Liability round trip"
            <| fun () ->
                Expect.equal
                    (Ok ItemKind.Liability)
                    (ItemKind.Liability |> ItemKind.toString |> ItemKind.parse)
                    "Could not round trip Liability"

            testCase "Parse rejects invalid value"
            <| fun () -> Expect.isError (ItemKind.parse "foo") "ItemKind accepted invalid value 'foo'"
        ]

    [<Tests>]
    let termTests =
        testList "Term" [
            testCase "Round trip Current"
            <| fun () ->
                Expect.equal
                    (Ok Term.Current)
                    (Term.Current |> Term.toString |> Term.parse)
                    "Could not round trip Current"

            testCase "Round trip NonCurrent"
            <| fun () ->
                Expect.equal
                    (Ok Term.NonCurrent)
                    (Term.NonCurrent |> Term.toString |> Term.parse)
                    "Could not round trip NonCurrent"

            testCase "Parse rejects invalid value"
            <| fun () -> Expect.isError (Term.parse "foo") "Term accepted invalid value 'foo'"
        ]
