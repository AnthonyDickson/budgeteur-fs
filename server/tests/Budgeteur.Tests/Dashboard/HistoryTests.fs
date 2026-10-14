namespace Budgeteur.Tests.Dashboard

module HistoryTests =
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
    open Budgeteur.Feature.Dashboard

    let private okOrFail label =
        function
        | Ok value -> value
        | Error error -> failtestf "%s: expected Ok, got %A" label error

    let private date (month : int) (day : int) = DateOnly (2026, month, day)

    let private today = date 10 14

    let private everyday : Account = {
        Id = Guid.NewGuid ()
        Number = None
        Name = AccountName.create "Everyday" |> okOrFail "name"
        Term = Current
        ClosedOn = None
    }

    let private car : BalanceSheetItem = {
        Id = Guid.NewGuid ()
        Name = ItemName.create "Car" |> okOrFail "name"
        Side = Asset
        Term = NonCurrent
        ClosedOn = None
    }

    let private balance (month : int) (day : int) (amount : decimal) =
        {
            AsOf = date month day
            Balance = Money.create amount
        }
        : BalanceObservation

    let private value (month : int) (day : int) (amount : decimal) =
        {
            AsOf = date month day
            Value = Value.create amount |> okOrFail "value"
        }
        : ItemObservation

    /// <summary>A car valued from July, and an everyday account opened with
    /// its first balance in August.</summary>
    let private balanceHistory : BalanceSheetHistory = {
        ItemHistories = [ car, [ value 7 10 10000m; value 9 15 9000m ] ]
        AccountHistories = [
            everyday, [ balance 8 20 4000m; balance 10 5 6000m ]
        ]
    }

    let private salary : Tag = {
        Id = Guid.NewGuid ()
        Name = TagName.unsafeFromString "Salary"
        Color = TagColor.unsafeFromString "#16A34A"
        Kind = Income
    }

    let private entry (month : int) (day : int) amount tag : Entry = {
        Date = date month day
        Amount = amount
        Tag = tag
    }

    /// <summary>Salary and spending from 1 August: two baseline months and
    /// the month to date.</summary>
    let private entries = [
        entry 8 1 5000m (Some salary)
        entry 8 9 -3000m None
        entry 9 1 5000m (Some salary)
        entry 9 9 -1000m None
        entry 10 1 5000m (Some salary)
        entry 10 9 -500m None
        entry 10 20 -100m None
    ]

    let private compute today balanceHistory firstTransaction entries =
        Dashboard.compute
            (Dashboard.periodsFor today balanceHistory firstTransaction)
            balanceHistory
            entries

    let private figures = compute today balanceHistory (Some (date 8 1)) entries

    let private monthOf (month : int) (months : HistoryMonth list) =
        match
            months
            |> List.tryFind (fun history ->
                ReportingPeriod.fromDate history.Month = date month 1)
        with
        | Some history -> history
        | None -> failtestf "no history for month %i" month

    let private monthStarts (months : HistoryMonth list) =
        months |> List.map (_.Month >> ReportingPeriod.fromDate)

    [<Tests>]
    let tests =
        testList "Dashboard history" [
            testCase "the history starts at the first observation"
            <| fun () ->
                Expect.equal
                    (monthStarts figures.History)
                    [ date 7 1; date 8 1; date 9 1; date 10 1 ]
                    "the car's July value starts it"

            testCase "each month has its statement and closing position"
            <| fun () ->
                let september = figures.History |> monthOf 9

                Expect.equal
                    (september.Income, september.Expenses, september.NetIncome)
                    (5000m, 1000m, 4000m)
                    "September's statement"

                Expect.equal
                    september.NetWorth
                    (Some 13000m)
                    "the car's September value and August's balance"

                Expect.equal
                    september.WorkingCapital
                    (Some 4000m)
                    "the account only"

            testCase "the month to date runs to today"
            <| fun () ->
                let october = figures.History |> monthOf 10

                Expect.equal october.ClosingDate today "closes today"
                Expect.isFalse october.Complete "is partial"

                Expect.equal october.Expenses 500m "the 20th is after today"

                Expect.equal october.NetWorth (Some 15000m) "as of today"

            testCase "a month before any observation has no position"
            <| fun () ->
                let history =
                    compute
                        today
                        {
                            ItemHistories = []
                            AccountHistories = [ everyday, [ balance 9 1 1m ] ]
                        }
                        (Some (date 8 1))
                        entries

                let august = history.History |> monthOf 8

                Expect.isNone august.NetWorth "no balance yet"
                Expect.isNone august.WorkingCapital "no balance yet"

            testCase "totals cover the baseline months only"
            <| fun () ->
                Expect.equal
                    figures.Totals
                    (Some {
                        MonthCount = 2
                        Income = 10000m
                        Expenses = 4000m
                        NetIncome = 6000m
                        SavingsRate = Some 60m
                        AverageIncome = 5000m
                        AverageExpenses = 2000m
                        AverageNetIncome = 3000m
                    })
                    "August and September, not July or October"

            testCase "there are no totals without baseline months"
            <| fun () ->
                let noBaseline = compute today balanceHistory None []

                Expect.isNone noBaseline.Totals "no transactions"
                Expect.isNone noBaseline.Position.Runway "nothing to divide by"

            testCase "runway is working capital in months of expenses"
            <| fun () ->
                Expect.equal
                    figures.Position.Runway
                    (Some 3m)
                    "6000 over 2000 a month"

                Expect.equal
                    (Dashboard.runway -500m figures.Totals)
                    (Some 0m)
                    "negative working capital is no runway"

                Expect.equal
                    (Dashboard.runway 1000m figures.Totals)
                    (Some 0.5m)
                    "rounded to one decimal place"

                let noExpenses =
                    figures.Totals
                    |> Option.map (fun totals -> {
                        totals with
                            AverageExpenses = 0m
                    })

                Expect.isNone
                    (Dashboard.runway 1000m noExpenses)
                    "no expenses to divide by"

            testCase "the position shows the oldest as-of date"
            <| fun () ->
                Expect.equal
                    figures.Position.OldestAsOf
                    (Some (date 9 15))
                    "the car's value is older than the account's balance"

                Expect.isFalse figures.Position.IsEmpty "has lines"

            testCase "a user with no data has an empty position"
            <| fun () ->
                let empty =
                    compute
                        today
                        {
                            ItemHistories = []
                            AccountHistories = []
                        }
                        None
                        []

                Expect.isTrue empty.Position.IsEmpty "nothing recorded"
                Expect.isNone empty.Position.OldestAsOf "no as-of date"

                Expect.equal
                    (monthStarts empty.History)
                    [ date 10 1 ]
                    "today's month only"
        ]
