namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.Account
open Budgeteur.Domain.Money

module AccountTests =
    let private canonical (number : string) =
        AccountNumber.create number |> Result.map AccountNumber.value

    [<Tests>]
    let accountNumberTests =
        testList "AccountNumber" [
            testCase "bank account numbers have one canonical form"
            <| fun () ->
                // Banks print the suffix with two or three digits, and some
                // drop the account's leading zeros, but transfer detection
                // compares numbers from different statements.
                let forms = [
                    "12-3456-0789012-00"
                    "12-3456-0789012-000"
                    "12-3456-789012-00"
                    "12 3456 0789012 00"
                    "  12-3456-0789012-00  "
                    "123456078901200"
                    "1234560789012000"
                ]

                for form in forms do
                    Expect.equal
                        (canonical form)
                        (Ok "12-3456-0789012-000")
                        $"\"{form}\" should have the canonical form"

            testCase "the suffix keeps its value when padded"
            <| fun () ->
                Expect.equal
                    (canonical "12-3456-0789012-01")
                    (Ok "12-3456-0789012-001")
                    "a two-digit suffix is padded on the left"

                Expect.notEqual
                    (canonical "12-3456-0789012-01")
                    (canonical "12-3456-0789012-00")
                    "different suffixes are different accounts"

            testCase "masked card numbers are kept as printed"
            <| fun () ->
                Expect.equal
                    (canonical "XXXX-XXXX-XXXX-1234")
                    (Ok "XXXX-XXXX-XXXX-1234")
                    "an ASB card number"

                Expect.equal
                    (canonical "4835-****-****-1234")
                    (Ok "4835-****-****-1234")
                    "a card number masked with asterisks"

            testCase "anything else is rejected"
            <| fun () ->
                let invalid = [
                    ""
                    "12-3456-07890123-00"
                    "12-3456-0789012-0000"
                    "1-3456-0789012-00"
                    "12345607890"
                    "1234-5678-9012-3456"
                    "XXXX-XXXX-XXXX-XXXX"
                    "Savings"
                    // Arabic-Indic digits, which \d would accept.
                    "١٢-٣٤٥٦-٠٧٨٩٠١٢-٠٠"
                ]

                for number in invalid do
                    Expect.isError
                        (AccountNumber.create number)
                        $"\"{number}\" should be rejected"
        ]

    [<Tests>]
    let accountNameTests =
        testList "AccountName" [
            testCase "a statement's account is named after its number"
            <| fun () ->
                let number =
                    AccountNumber.create "XXXX-XXXX-XXXX-1234"
                    |> Result.defaultWith (fun error -> failtestf "%A" error)

                Expect.equal
                    (AccountName.value (AccountName.ofNumber number None))
                    "XXXX-XXXX-XXXX-1234"
                    "without a product name"

                Expect.equal
                    (AccountName.value (
                        AccountName.ofNumber number (Some "Visa Light")
                    ))
                    "XXXX-XXXX-XXXX-1234 (Visa Light)"
                    "with the product name in parentheses"

                let longName =
                    AccountName.ofNumber number (Some (String ('x', 200)))

                Expect.equal
                    (AccountName.value longName).Length
                    AccountName.MaxLength
                    "a long product name is truncated"

            testCase "a name is trimmed and cannot be blank"
            <| fun () ->
                Expect.equal
                    (AccountName.create "  Savings  "
                     |> Result.map AccountName.value)
                    (Ok "Savings")
                    "the name is trimmed"

                Expect.isError (AccountName.create "   ") "blank is rejected"
        ]

    [<Tests>]
    let observationTests =
        let observation (day : int) (balance : decimal) = {
            AsOf = DateOnly (2026, 3, day)
            Balance = Money.create balance
        }

        testList "BalanceObservation" [
            testCase "the latest observation is current, whatever the order"
            <| fun () ->
                let latest = observation 20 150m

                let observations = [
                    observation 10 100m
                    latest
                    observation 15 -50m
                ]

                Expect.equal
                    (BalanceObservation.current observations)
                    (Some latest)
                    "the 20th is the latest"

            testCase "an account without observations has an unknown balance"
            <| fun () ->
                Expect.isNone
                    (BalanceObservation.current [])
                    "unknown, not zero"

            testCase "a manual balance cannot be dated in the future"
            <| fun () ->
                let now = DateTimeOffset (2026, 3, 8, 12, 0, 0, TimeSpan.Zero)

                Expect.equal
                    (BalanceObservation.create
                        now
                        (DateOnly (2026, 3, 9))
                        -12.345m)
                    (Ok (observation 9 -12.35m))
                    "tomorrow is accepted, and the balance rounds to cents"

                Expect.isError
                    (BalanceObservation.create now (DateOnly (2026, 3, 10)) 1m)
                    "two days ahead is rejected"
        ]
