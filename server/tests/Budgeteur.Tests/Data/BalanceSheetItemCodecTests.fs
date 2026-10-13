namespace Budgeteur.Tests

module BalanceSheetItemCodecTests =
    open System
    open Expecto

    open Budgeteur.Data
    open Budgeteur.Domain.BalanceSheetItem
    open Budgeteur.Domain.Side
    open Budgeteur.Domain.Term

    let private okOrFail label =
        function
        | Ok value -> value
        | Error error ->
            failtestf "%s: expected Ok, but got Error %A" label error

    [<Tests>]
    let codecTests =
        let userId = "test"

        let tests =
            List.allPairs [ Side.Asset; Side.Liability ] [
                Term.Current
                Term.NonCurrent
            ]
            |> List.map (fun (side, term) ->
                let sideName = Side.toString side
                let termName = Term.toString term

                testCase
                    $"codec round trips for side {sideName} and term {termName}"
                    (fun () ->
                        let item : BalanceSheetItem = {
                            Id = Guid.CreateVersion7 ()
                            Name = ItemName.create "Foo" |> okOrFail "Name"
                            Side = side
                            Term = term
                            ClosedOn = Some (DateOnly (2026, 3, 8))
                        }

                        let row = BalanceSheetItemCodec.toRow item userId
                        let item' = BalanceSheetItemCodec.fromRow row

                        Expect.equal
                            item'
                            item
                            "Decoded BalanceSheetItem did not match the \
                            original"))

        testList "BalanceSheetItem codec" tests
