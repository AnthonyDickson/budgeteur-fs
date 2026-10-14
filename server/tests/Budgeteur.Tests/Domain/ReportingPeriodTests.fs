namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.ReportingPeriod

module ReportingPeriodTests =
    let private dates (period : ReportingPeriod) =
        ReportingPeriod.fromDate period, ReportingPeriod.toDate period

    let private containing frequency (year : int) (month : int) (day : int) =
        ReportingPeriod.containing frequency (DateOnly (year, month, day))

    [<Tests>]
    let tests =
        testList "ReportingPeriod" [
            testCase "a month runs from its first day to its last"
            <| fun () ->
                Expect.equal
                    (dates (containing Monthly 2028 2 15))
                    (DateOnly (2028, 2, 1), DateOnly (2028, 2, 29))
                    "February of a leap year has 29 days"

                Expect.equal
                    (dates (containing Monthly 2026 2 28))
                    (DateOnly (2026, 2, 1), DateOnly (2026, 2, 28))
                    "February of a common year has 28"

            testCase "quarters are calendar quarters"
            <| fun () ->
                Expect.equal
                    (dates (containing Quarterly 2026 3 31))
                    (DateOnly (2026, 1, 1), DateOnly (2026, 3, 31))
                    "31 March is in the first quarter"

                Expect.equal
                    (dates (containing Quarterly 2026 4 1))
                    (DateOnly (2026, 4, 1), DateOnly (2026, 6, 30))
                    "1 April starts the second"

                Expect.equal
                    (dates (containing Quarterly 2026 12 31))
                    (DateOnly (2026, 10, 1), DateOnly (2026, 12, 31))
                    "31 December is in the fourth"

            testCase "a financial year runs from 1 April to 31 March"
            <| fun () ->
                Expect.equal
                    (dates (containing FinancialYear 2026 3 31))
                    (DateOnly (2025, 4, 1), DateOnly (2026, 3, 31))
                    "31 March ends the year that started the April before"

                Expect.equal
                    (dates (containing FinancialYear 2026 4 1))
                    (DateOnly (2026, 4, 1), DateOnly (2027, 3, 31))
                    "1 April starts the next"

                Expect.equal
                    (dates (containing CalendarYear 2026 4 1))
                    (DateOnly (2026, 1, 1), DateOnly (2026, 12, 31))
                    "a calendar year is January to December"

            testCase "periods step back and forward across year boundaries"
            <| fun () ->
                let january = containing Monthly 2026 1 10

                Expect.equal
                    (dates (ReportingPeriod.previous january))
                    (DateOnly (2025, 12, 1), DateOnly (2025, 12, 31))
                    "the month before January is December"

                let fourthQuarter = containing Quarterly 2025 11 1

                Expect.equal
                    (dates (ReportingPeriod.next fourthQuarter))
                    (DateOnly (2026, 1, 1), DateOnly (2026, 3, 31))
                    "the quarter after the fourth is the first"

                let year = containing FinancialYear 2026 6 1

                Expect.equal
                    (ReportingPeriod.previous year
                     |> ReportingPeriod.next
                     |> dates)
                    (dates year)
                    "back then forward is the same year"

            testCase "a period is complete once its last day has come"
            <| fun () ->
                let march = containing Monthly 2026 3 1

                Expect.isFalse
                    (ReportingPeriod.isComplete (DateOnly (2026, 3, 30)) march)
                    "to date on the 30th"

                Expect.isTrue
                    (ReportingPeriod.isComplete (DateOnly (2026, 3, 31)) march)
                    "complete on its last day"

            testCase "labels name the period"
            <| fun () ->
                let label frequency =
                    containing frequency 2026 3 15 |> ReportingPeriod.label

                Expect.equal (label Monthly) "March 2026" "a month"
                Expect.equal (label Quarterly) "Q1 2026" "a quarter"
                Expect.equal (label CalendarYear) "2026" "a calendar year"

                Expect.equal
                    (label FinancialYear)
                    "2025/26"
                    "a financial year by both years"

                Expect.equal
                    (containing FinancialYear 2099 4 1 |> ReportingPeriod.label)
                    "2099/00"
                    "the second year wraps at a century"

            testCase "frequencies round trip"
            <| fun () ->
                for frequency in
                    [ Monthly; Quarterly; CalendarYear; FinancialYear ] do
                    Expect.equal
                        (frequency |> Frequency.toString |> Frequency.parse)
                        (Ok frequency)
                        $"%A{frequency}"

                Expect.isError (Frequency.parse "Weekly") "unknown frequency"
        ]
