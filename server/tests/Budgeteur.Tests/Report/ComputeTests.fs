namespace Budgeteur.Tests.Report

module ComputeTests =
    open System
    open Expecto

    open Budgeteur.Domain.Account
    open Budgeteur.Domain.BalanceSheet
    open Budgeteur.Domain.BalanceSheetItem
    open Budgeteur.Domain.IncomeStatement
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.ReportingPeriod
    open Budgeteur.Domain.Side
    open Budgeteur.Domain.Tag
    open Budgeteur.Domain.Term
    open Budgeteur.Feature.Report

    let private okOrFail label =
        function
        | Ok value -> value
        | Error error -> failtestf "%s: expected Ok, got %A" label error

    let private date (month : int) (day : int) = DateOnly (2026, month, day)

    let private house : BalanceSheetItem = {
        Id = Guid.NewGuid ()
        Name = ItemName.create "House" |> okOrFail "name"
        Side = Asset
        Term = NonCurrent
        ClosedOn = None
    }

    let private everyday : Account = {
        Id = Guid.NewGuid ()
        Number = None
        Name = AccountName.create "Everyday" |> okOrFail "name"
        Term = Current
        ClosedOn = None
    }

    let private value (month : int) (day : int) (amount : decimal) =
        {
            AsOf = date month day
            Value = Value.create amount |> okOrFail "value"
        }
        : ItemObservation

    let private balance (month : int) (day : int) (amount : decimal) =
        {
            AsOf = date month day
            Balance = Money.create amount
        }
        : BalanceObservation

    /// A house revalued from 400k to 410k in March, and an account that
    /// gains the month's 3k of savings.
    let private history : BalanceSheetHistory = {
        ItemHistories = [ house, [ value 1 10 400000m; value 3 20 410000m ] ]
        AccountHistories = [
            everyday, [ balance 2 25 5000m; balance 3 31 8000m ]
        ]
    }

    let private salary : Tag = {
        Id = Guid.NewGuid ()
        Name = TagName.unsafeFromString "Salary"
        Color = TagColor.unsafeFromString "#16A34A"
        Kind = Income
    }

    let private entries : Entry list = [
        { Amount = 5000m; Tag = Some salary }
        { Amount = -2000m; Tag = None }
    ]

    let private month (m : int) =
        ReportingPeriod.containing Monthly (date m 1)

    /// <summary>The monthly reports on <c>today</c> for data from 10
    /// January.</summary>
    let private rangeOn (today : DateOnly) =
        Report.range Monthly today (Some (date 1 10))

    [<Tests>]
    let tests =
        testList "Report" [
            testCase "a report splits the change in net worth"
            <| fun () ->
                let report =
                    Report.compute
                        (date 10 14)
                        (rangeOn (date 10 14))
                        (month 3)
                        history
                        entries

                Expect.equal
                    (BalanceSheet.netWorth report.Opening)
                    405000m
                    "the house and account at the end of February"

                Expect.equal
                    (BalanceSheet.netWorth report.Closing)
                    418000m
                    "and at the end of March"

                Expect.equal
                    report.Change
                    (Some {
                        NetWorth = 13000m
                        OtherChanges = 10000m
                        WorkingCapital = 3000m
                    })
                    "3k saved, 10k revalued, and 3k more current"

                Expect.equal report.SavingsRate (Some 60m) "3k of 5k income"
                Expect.isTrue report.Complete "March is over by October"
                Expect.equal report.ClosingDate (date 3 31) "the month's end"

            testCase "the first report's change is not meaningful"
            <| fun () ->
                // The first observation is in January, so January opens on an
                // empty sheet.
                let report =
                    Report.compute
                        (date 10 14)
                        (rangeOn (date 10 14))
                        (month 1)
                        history
                        []

                Expect.isNone
                    report.Change
                    "an empty opening sheet makes the change meaningless"

                Expect.isFalse report.HasPrevious "January has the first data"
                Expect.isTrue report.HasNext "February has a report"

            testCase "a report to date closes on today"
            <| fun () ->
                let report =
                    Report.compute
                        (date 3 15)
                        (rangeOn (date 3 15))
                        (month 3)
                        history
                        entries

                Expect.isFalse report.Complete "March is not over"
                Expect.equal report.ClosingDate (date 3 15) "closes on today"

                Expect.equal
                    (BalanceSheet.netWorth report.Closing)
                    405000m
                    "the later March observations are not yet in"

                Expect.isFalse report.HasNext "nothing after today's period"

            testCase "the default period is the latest complete one"
            <| fun () ->
                let pick firstDate requested =
                    Report.period
                        (Report.range Monthly (date 3 15) firstDate)
                        requested
                    |> Option.map ReportingPeriod.fromDate

                Expect.equal
                    (pick (Some (date 1 10)) None)
                    (Some (date 2 1))
                    "February, since March is to date"

                Expect.equal
                    (pick (Some (date 3 2)) None)
                    (Some (date 3 1))
                    "March when the data starts in March"

                Expect.equal (pick None None) (Some (date 3 1)) "no data yet"

                Expect.equal
                    (pick (Some (date 1 10)) (Some (date 1 31)))
                    (Some (date 1 1))
                    "the period containing the date"

                Expect.isNone
                    (pick (Some (date 1 10)) (Some (date 4 1)))
                    "no report after today's period"

                Expect.isNone
                    (pick (Some (date 1 10)) (Some (DateOnly (2025, 12, 31))))
                    "no report before the first data"
        ]
