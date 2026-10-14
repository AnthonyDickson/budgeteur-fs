namespace Budgeteur.Tests.Dashboard

module PeriodsTests =
    open System
    open Expecto

    open Budgeteur.Domain.IncomeStatement
    open Budgeteur.Domain.ReportingPeriod
    open Budgeteur.Feature.Dashboard

    let private dates (period : Period) =
        Period.fromDate period, Period.toDate period

    let private month (year : int) (month : int) =
        ReportingPeriod.containing Monthly (DateOnly (year, month, 1))

    let private sameDays (today : DateOnly) (year : int) (m : int) =
        dates (Dashboard.sameDays today (month year m))

    /// <summary>Each month's first day, for readable comparisons.</summary>
    let private starts (months : ReportingPeriod list) =
        months |> List.map ReportingPeriod.fromDate

    let private monthsFrom (year : int) (m : int) (count : int) =
        List.init count (fun offset -> DateOnly(year, m, 1).AddMonths offset)

    [<Tests>]
    let tests =
        testList "Dashboard periods" [
            testCase "the baseline days run to today's day of the month"
            <| fun () ->
                Expect.equal
                    (sameDays (DateOnly (2026, 10, 14)) 2026 9)
                    (DateOnly (2026, 9, 1), DateOnly (2026, 9, 14))
                    "on 14 October, September's days are 1 to 14"

                Expect.equal
                    (sameDays (DateOnly (2027, 1, 15)) 2026 12)
                    (DateOnly (2026, 12, 1), DateOnly (2026, 12, 15))
                    "the days cross a year boundary"

            testCase "the baseline day is clamped to a shorter month"
            <| fun () ->
                Expect.equal
                    (sameDays (DateOnly (2026, 3, 30)) 2026 2)
                    (DateOnly (2026, 2, 1), DateOnly (2026, 2, 28))
                    "on 30 March, February's days are 1 to 28"

                Expect.equal
                    (sameDays (DateOnly (2028, 3, 30)) 2028 2)
                    (DateOnly (2028, 2, 1), DateOnly (2028, 2, 29))
                    "in a leap year they are 1 to 29"

            testCase "on a month's last day the whole baseline month is used"
            <| fun () ->
                Expect.equal
                    (sameDays (DateOnly (2026, 9, 30)) 2026 8)
                    (DateOnly (2026, 8, 1), DateOnly (2026, 8, 31))
                    "on 30 September, the whole of August"

                Expect.equal
                    (sameDays (DateOnly (2027, 2, 28)) 2027 1)
                    (DateOnly (2027, 1, 1), DateOnly (2027, 1, 31))
                    "on 28 February, the whole of January"

                Expect.equal
                    (sameDays (DateOnly (2028, 2, 28)) 2028 1)
                    (DateOnly (2028, 1, 1), DateOnly (2028, 1, 28))
                    "28 February of a leap year is not its last day"

            testCase "a user with years of data has twelve months and this one"
            <| fun () ->
                let today = DateOnly (2026, 10, 14)

                let periods =
                    Dashboard.periods
                        today
                        (Some (DateOnly (2020, 1, 1)))
                        (Some (DateOnly (2020, 1, 1)))

                Expect.equal
                    (starts periods.HistoryMonths)
                    (monthsFrom 2025 10 13)
                    "the history runs from October 2025 to October 2026"

                Expect.equal
                    (starts periods.BaselineMonths)
                    (monthsFrom 2025 10 12)
                    "the baseline months are the twelve complete ones"

                Expect.equal
                    (dates periods.MonthToDate)
                    (DateOnly (2026, 10, 1), today)
                    "the month to date runs from the first to today"

                Expect.equal
                    (dates (Dashboard.readPeriod periods))
                    (DateOnly (2025, 10, 1), today)
                    "one read covers the whole history"

            testCase "in January the history starts in the January before"
            <| fun () ->
                let periods =
                    Dashboard.periods
                        (DateOnly (2027, 1, 1))
                        (Some (DateOnly (2020, 1, 1)))
                        (Some (DateOnly (2020, 1, 1)))

                Expect.equal
                    (starts periods.HistoryMonths)
                    (monthsFrom 2026 1 13)
                    "January 2026 to January 2027"

            testCase "the history starts at the month of the first data"
            <| fun () ->
                let periods =
                    Dashboard.periods
                        (DateOnly (2026, 10, 14))
                        (Some (DateOnly (2026, 5, 20)))
                        (Some (DateOnly (2026, 6, 10)))

                Expect.equal
                    (starts periods.HistoryMonths)
                    (monthsFrom 2026 5 6)
                    "an observation in May starts the history in May"

                Expect.equal
                    (starts periods.BaselineMonths)
                    (monthsFrom 2026 7 3)
                    "June has partial data, so the baseline starts in July"

            testCase
                "a month starting on the first transaction is a baseline month"
            <| fun () ->
                let periods =
                    Dashboard.periods
                        (DateOnly (2026, 10, 14))
                        (Some (DateOnly (2026, 8, 1)))
                        (Some (DateOnly (2026, 8, 1)))

                Expect.equal
                    (starts periods.BaselineMonths)
                    (monthsFrom 2026 8 2)
                    "August and September"

            testCase "a user with observations only has no baseline months"
            <| fun () ->
                let periods =
                    Dashboard.periods
                        (DateOnly (2026, 10, 14))
                        (Some (DateOnly (2026, 3, 1)))
                        None

                Expect.equal
                    (List.length periods.HistoryMonths)
                    8
                    "March to October"

                Expect.isEmpty periods.BaselineMonths "no transactions"

            testCase "a user with no data has today's month only"
            <| fun () ->
                let periods =
                    Dashboard.periods (DateOnly (2026, 10, 14)) None None

                Expect.equal
                    (starts periods.HistoryMonths)
                    [ DateOnly (2026, 10, 1) ]
                    "October only"

                Expect.isEmpty periods.BaselineMonths "nothing to average"

            testCase
                "first data after today starts the history at today's month"
            <| fun () ->
                let periods =
                    Dashboard.periods
                        (DateOnly (2026, 10, 14))
                        (Some (DateOnly (2026, 12, 1)))
                        (Some (DateOnly (2026, 12, 1)))

                Expect.equal
                    (starts periods.HistoryMonths)
                    [ DateOnly (2026, 10, 1) ]
                    "a future-dated transaction does not empty the history"
        ]
