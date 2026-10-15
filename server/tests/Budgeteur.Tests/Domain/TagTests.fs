namespace Budgeteur.Tests

open Expecto

open Budgeteur.Domain.Tag

module TagTests =
    [<Tests>]
    let tagColorTests =
        testList "TagColor" [
            testCase "every colour parses from its name"
            <| fun () ->
                for color in TagColor.all do
                    Expect.equal
                        (TagColor.parse (TagColor.toString color))
                        (Ok color)
                        $"{TagColor.toString color} should parse"

            testCase "hex colours and unknown names are rejected"
            <| fun () ->
                // Tags stored hex colours before they stored Catppuccin names.
                for value in [ "#22C55E"; "green"; "Grey"; "" ] do
                    Expect.isError
                        (TagColor.parse value)
                        $"\"{value}\" should be rejected"
        ]
