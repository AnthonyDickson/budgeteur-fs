namespace Budgeteur.Tests.Dashboard

module MonthTests =
    open System
    open Expecto

    open Budgeteur.Domain.IncomeStatement
    open Budgeteur.Domain.Tag
    open Budgeteur.Feature.Dashboard

    let private tag (name : string) (kind : TagKind) : Tag = {
        Id = Guid.CreateVersion7 ()
        Name = TagName.unsafeFromString name
        Color = TagColor.unsafeFromString "#6366F1"
        Kind = kind
    }

    let private salary = tag "Salary" Income
    let private rent = tag "Rent" Expense
    let private groceries = tag "Groceries" Expense
    let private fuel = tag "Fuel" Expense

    let private entry (month : int) (day : int) amount tag : Entry = {
        Date = DateOnly (2026, month, day)
        Amount = amount
        Tag = tag
    }

    let private today = DateOnly (2026, 10, 14)

    /// <summary>The figures on 14 October for a user whose first transaction
    /// was on <c>firstTransaction</c>.</summary>
    let private monthFrom (firstTransaction : DateOnly) entries =
        Dashboard.month
            (Dashboard.periods
                today
                (Some firstTransaction)
                (Some firstTransaction))
            entries

    /// <summary>The figures on 14 October with August and September as the
    /// baseline months.</summary>
    let private month entries =
        monthFrom (DateOnly (2026, 8, 1)) entries

    let private lineOf (tag : Tag option) (lines : MonthLine list) =
        match lines |> List.tryFind (fun line -> line.Tag = tag) with
        | Some line -> line
        | None -> failtest "no line for the tag"

    let private comparison (figure : Figure) =
        figure.Comparison |> Option.defaultWith (fun () -> failtest "none")

    [<Tests>]
    let tests =
        testList "Dashboard month" [
            testCase "a baseline is the mean over the same days of each month"
            <| fun () ->
                let figures =
                    month [
                        entry 8 5 -100m (Some groceries)
                        entry 8 20 -500m (Some groceries)
                        entry 9 14 -300m (Some groceries)
                        entry 10 3 -250m (Some groceries)
                    ]

                Expect.equal
                    (comparison figures.Expenses)
                    {
                        Baseline = 200m
                        Change = 50m
                        ChangePercent = Some 25m
                    }
                    "the 20th is after the 14th, so the mean is of 100 and 300"

                Expect.equal
                    (lineOf (Some groceries) figures.ExpenseLines).Comparison
                    (figures.Expenses.Comparison)
                    "the line has the same baseline"

                Expect.equal figures.BaselineMonthCount 2 "August and September"

            testCase "a baseline is rounded to cents"
            <| fun () ->
                let figures =
                    monthFrom (DateOnly (2026, 7, 1)) [
                        entry 7 1 -100m (Some groceries)
                    ]

                Expect.equal
                    (comparison figures.Expenses).Baseline
                    33.33m
                    "100 over three months"

            testCase "a usual expense with nothing this month is a zero line"
            <| fun () ->
                let figures =
                    month [
                        entry 8 1 -2000m (Some rent)
                        entry 9 1 -2000m (Some rent)
                        entry 10 3 -250m (Some groceries)
                        entry 10 4 -20m None
                    ]

                Expect.equal
                    (figures.ExpenseLines |> List.map _.Tag)
                    [ Some groceries; Some rent; None ]
                    "the zero line sorts by amount, before the untagged line"

                let rentLine = lineOf (Some rent) figures.ExpenseLines

                Expect.equal rentLine.Amount 0m "nothing this month"
                Expect.equal rentLine.Share (Some 0m) "a zero share"

                Expect.equal
                    rentLine.Comparison
                    (Some {
                        Baseline = 2000m
                        Change = -2000m
                        ChangePercent = Some -100m
                    })
                    "compared with its mean"

            testCase "a line new this month has no change percentage"
            <| fun () ->
                let figures =
                    month [
                        entry 8 1 -2000m (Some rent)
                        entry 10 3 -80m (Some fuel)
                    ]

                Expect.equal
                    (lineOf (Some fuel) figures.ExpenseLines).Comparison
                    (Some {
                        Baseline = 0m
                        Change = 80m
                        ChangePercent = None
                    })
                    "a zero baseline has no percentage"

            testCase "a negative baseline has no change percentage"
            <| fun () ->
                let figures =
                    month [
                        entry 8 1 1000m (Some salary)
                        entry 8 2 -3000m (Some rent)
                        entry 10 1 1000m (Some salary)
                    ]

                Expect.equal
                    (comparison figures.NetIncome)
                    {
                        Baseline = -1000m
                        Change = 2000m
                        ChangePercent = None
                    }
                    "net income averaged -1000 over two months"

            testCase
                "the savings rate baseline is the rate of the baseline means"
            <| fun () ->
                let figures =
                    month [
                        entry 8 1 1000m (Some salary)
                        entry 8 2 -900m (Some rent)
                        entry 9 1 9000m (Some salary)
                        entry 9 2 -900m (Some rent)
                        entry 10 1 5000m (Some salary)
                        entry 10 2 -1500m (Some rent)
                    ]

                Expect.equal figures.SavingsRate (Some 70m) "3500 of 5000"

                Expect.equal
                    figures.SavingsRateBaseline
                    (Some 82m)
                    "4100 of 5000, not the mean of 10% and 90%"

                Expect.equal figures.SavingsRateChange (Some -12m) "in points"

            testCase "with no baseline months nothing is compared"
            <| fun () ->
                let figures =
                    monthFrom (DateOnly (2026, 9, 10)) [
                        entry 9 10 3000m (Some salary)
                        entry 10 1 5000m (Some salary)
                        entry 10 3 -250m (Some groceries)
                    ]

                Expect.equal figures.BaselineMonthCount 0 "still building"
                Expect.isNone figures.Income.Comparison "no income baseline"

                Expect.isNone
                    figures.SavingsRateBaseline
                    "no savings rate baseline"

                Expect.isNone figures.SavingsRateChange "no change"

                Expect.equal
                    (figures.IncomeLines |> List.map _.Comparison)
                    [ None ]
                    "September's salary is not a baseline line"

            testCase "the latest transaction is the month's last date"
            <| fun () ->
                let figures =
                    month [
                        entry 9 30 -10m (Some fuel)
                        entry 10 9 -10m (Some fuel)
                        entry 10 3 -10m (Some fuel)
                    ]

                Expect.equal
                    figures.LatestTransaction
                    (Some (DateOnly (2026, 10, 9)))
                    "9 October"

                Expect.isNone
                    (month [ entry 9 30 -10m (Some fuel) ]).LatestTransaction
                    "none this month"
        ]
