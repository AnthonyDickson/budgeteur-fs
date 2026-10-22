namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.Rule
open Budgeteur.Domain.Transaction

module RuleTests =
    let private okOrFail label =
        function
        | Ok value -> value
        | Error error ->
            failtestf "%s: expected Ok, but got Error %A" label error

    let private pattern value =
        RulePattern.create value |> okOrFail "pattern"

    let private description value =
        TransactionDescription.create value |> okOrFail "description"

    let private rule (value : string) : Rule = {
        Id = Guid.NewGuid ()
        Pattern = pattern value
        Target = RuleTarget.Tag (Guid.NewGuid ())
    }

    /// The pattern of the winning rule, so failures name the pattern.
    let private winningPattern rules text =
        Rule.winner rules (description text)
        |> Option.map (fun rule -> RulePattern.value rule.Pattern)

    [<Tests>]
    let matchTests =
        testList "RulePattern.matches" [
            testCase "matches anywhere in the description"
            <| fun () ->
                Expect.isTrue
                    (RulePattern.matches
                        (description "PAY Alice Highbrow Food Bob")
                        (pattern "Highbrow Food"))
                    "a pattern in the middle of the description should match"

            testCase "ignores case, including outside ASCII"
            <| fun () ->
                Expect.isTrue
                    (RulePattern.matches
                        (description "Café Ōtautahi")
                        (pattern "CAFÉ ŌTAUTAHI"))
                    "case should be ignored"

            testCase "does not ignore characters"
            <| fun () ->
                // Culture-sensitive comparison treats a soft hyphen as
                // ignorable, so it would match every description.
                Expect.isFalse
                    (RulePattern.matches
                        (description "COUNTDOWN")
                        (pattern (string (char 0x00AD))))
                    "a soft hyphen should not match a description without one"
        ]

    [<Tests>]
    let samePatternTests =
        testCase "RulePattern.same ignores case"
        <| fun () ->
            Expect.isTrue
                (RulePattern.same (pattern "Countdown") (pattern "COUNTDOWN"))
                "patterns differing by case should be the same"

    [<Tests>]
    let winnerTests =
        testList "Rule.winner" [
            testCase "no rule wins when none matches"
            <| fun () ->
                Expect.isNone
                    (winningPattern [ rule "COUNTDOWN" ] "New World")
                    "no rule should win"

            testCase "the longest matching pattern wins"
            <| fun () ->
                let rules = [
                    rule "COUNTDOWN"
                    rule "COUNTDOWN FUEL"
                    rule "FUEL"
                ]

                Expect.equal
                    (winningPattern rules "Countdown Fuel Ponsonby")
                    (Some "COUNTDOWN FUEL")
                    "the longer pattern should win"

            testCase "a longer pattern that does not match does not win"
            <| fun () ->
                let rules = [ rule "COUNTDOWN FUEL"; rule "COUNTDOWN" ]

                Expect.equal
                    (winningPattern rules "Countdown Ponsonby")
                    (Some "COUNTDOWN")
                    "only matching rules should compete"

            testCase "equal lengths are ordered by the comparison"
            <| fun () ->
                let rules = [ rule "bar"; rule "FOO"; rule "Baz" ]

                // Every order of the rules gives the same winner.
                for order in
                    [
                        rules
                        List.rev rules
                        List.permute (fun i -> (i + 1) % 3) rules
                    ] do
                    Expect.equal
                        (winningPattern order "foo bar baz")
                        (Some "bar")
                        "the pattern first under the comparison should win"

            testCase "the target does not change which rule wins"
            <| fun () ->
                let transferRule (value : string) = {
                    rule value with
                        Target = RuleTarget.Transfer
                }

                Expect.equal
                    (winningPattern
                        [ transferRule "TRANSFER TO"; rule "TRANSFER TO RENT" ]
                        "TRANSFER TO RENT ACCOUNT")
                    (Some "TRANSFER TO RENT")
                    "a longer tag pattern beats a shorter transfer pattern"

                Expect.equal
                    (winningPattern
                        [ rule "TRANSFER"; transferRule "TRANSFER TO SAVINGS" ]
                        "TRANSFER TO SAVINGS")
                    (Some "TRANSFER TO SAVINGS")
                    "a longer transfer pattern beats a shorter tag pattern"
        ]
