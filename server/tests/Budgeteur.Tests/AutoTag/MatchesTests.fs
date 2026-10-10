namespace Budgeteur.Tests.AutoTag

module MatchesTests =
    open Expecto

    open Budgeteur.Domain.Rule
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.AutoTag

    let private matches (pattern : string) (descriptions : string list) =
        AutoTag.matches
            (RulePattern.unsafeFromString pattern)
            (List.map TransactionDescription.unsafeFromString descriptions)

    let private expected (count : int) (samples : string list) : Matches = {
        Count = count
        Samples = List.map TransactionDescription.unsafeFromString samples
    }

    [<Tests>]
    let tests =
        testList "AutoTag.matches" [
            testCase "counts every match and samples distinct descriptions"
            <| fun () ->
                Expect.equal
                    (matches "countdown" [
                        "Countdown Ponsonby"
                        "Rent"
                        "COUNTDOWN Grey Lynn"
                        "Countdown Ponsonby"
                    ])
                    (expected 3 [ "Countdown Ponsonby"; "COUNTDOWN Grey Lynn" ])
                    "samples should keep the most recent first"

            testCase "keeps at most five samples"
            <| fun () ->
                let descriptions = [ for i in 1..7 -> $"Countdown {i}" ]

                Expect.equal
                    (matches "Countdown" descriptions)
                    (expected 7 (List.truncate 5 descriptions))
                    "only the five most recent should be sampled"

            testCase "a pattern that matches nothing has no samples"
            <| fun () ->
                Expect.equal
                    (matches "Countdown" [ "Rent"; "Pak'nSave" ])
                    (expected 0 [])
                    "nothing should match"
        ]
