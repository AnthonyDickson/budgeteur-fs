namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.AsOfDate

module AsOfDateTests =
    [<Tests>]
    let tests =
        testList "AsOfDate" [
            testCase "the latest date is the server's UTC date plus one day"
            <| fun () ->
                // 11pm UTC on 8 March is already 9 March in New Zealand, so
                // a client there may send the 9th as today; a day later is
                // a mistake.
                let now = DateTimeOffset (2026, 3, 8, 23, 0, 0, TimeSpan.Zero)

                Expect.equal
                    (AsOfDate.validate now (DateOnly (2026, 3, 9)))
                    (Ok (DateOnly (2026, 3, 9)))
                    "the day after the UTC date is accepted"

                Expect.isError
                    (AsOfDate.validate now (DateOnly (2026, 3, 10)))
                    "two days after the UTC date is rejected"

                Expect.equal
                    (AsOfDate.validate now (DateOnly (2020, 1, 1)))
                    (Ok (DateOnly (2020, 1, 1)))
                    "past dates are accepted"

            testCase "the bound uses the instant's UTC date, not its offset"
            <| fun () ->
                // 5am on 9 March at +13:00 is 4pm on 8 March in UTC.
                let now =
                    DateTimeOffset (
                        2026,
                        3,
                        9,
                        5,
                        0,
                        0,
                        TimeSpan.FromHours 13.0
                    )

                Expect.equal
                    (AsOfDate.latest now)
                    (DateOnly (2026, 3, 9))
                    "the UTC date is the 8th, so the latest is the 9th"
        ]
