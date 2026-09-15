namespace Budgeteur.Tests

module BalanceSheetItemCodecTests =
    open System
    open Expecto

    open Budgeteur.Data
    open Budgeteur.Domain.BalanceSheetItem

    let private okOrFail label =
        function
        | Ok value -> value
        | Error error -> failtestf "%s: expected Ok, but got Error %A" label error

    [<Tests>]
    let codecTests =
        let userId = "test"

        let tests =
            List.allPairs [ ItemKind.Asset; ItemKind.Liability ] [ Term.Current; Term.NonCurrent ]
            |> List.map (fun (kind, term) ->
                testCase
                    $"codec round trips for kind {ItemKind.toString kind} and term {Term.toString term}"
                    (fun () ->
                        let sheetId = Guid.CreateVersion7 ()

                        let item : BalanceSheetItem = {
                            Id = Guid.CreateVersion7 ()
                            Name = ItemName.create "Foo" |> okOrFail "Name"
                            Kind = kind
                            Term = term
                            Balance = Balance.create 1.23m |> okOrFail "Balance"
                        }

                        let row = BalanceSheetItemCodec.toRow item userId
                        let item' = BalanceSheetItemCodec.fromRow row

                        Expect.equal item' item "Decoded BalanceSheetItem did not match the original"))

        testList "BalanceSheetItem codec" tests
