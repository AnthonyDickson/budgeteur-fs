namespace Budgeteur.Tests.IncomeStatement

module ComputeTests =
    open System
    open Expecto

    open Budgeteur.Domain.Tag
    open Budgeteur.Feature.IncomeStatement

    let private tag (name : string) (kind : TagKind) : Tag = {
        Id = Guid.CreateVersion7 ()
        Name = TagName.unsafeFromString name
        Color = TagColor.unsafeFromString "#6366F1"
        Kind = kind
    }

    let private period =
        match Period.create (DateOnly (2026, 10, 1)) (DateOnly (2026, 10, 31)) with
        | Ok period -> period
        | Error error -> failwith error

    let private entry (amount : decimal) (tag : Tag option) : Entry = { Amount = amount; Tag = tag }

    let private lineAmounts (lines : Line list) =
        lines
        |> List.map (fun line -> line.Tag |> Option.map (fun tag -> tag.Id), line.Amount)

    let private expenseAmounts (lines : ExpenseLine list) =
        lines
        |> List.map (fun line -> line.Tag |> Option.map (fun tag -> tag.Id), line.Amount)

    [<Tests>]
    let tests =
        testList "IncomeStatement.compute" [
            test "an empty period has no lines and zero totals" {
                let statement = IncomeStatement.compute period []

                Expect.isEmpty statement.IncomeLines "there should be no income lines"
                Expect.isEmpty statement.ExpenseLines "there should be no expense lines"
                Expect.equal statement.Income 0m "income should be zero"
                Expect.equal statement.Expenses 0m "expenses should be zero"
                Expect.equal statement.NetIncome 0m "net income should be zero"
                Expect.equal statement.UntaggedCount 0 "there should be no untagged transactions"
            }

            test "a refund reduces its expense tag rather than counting as income" {
                let groceries = tag "Groceries" Expense

                let statement =
                    IncomeStatement.compute period [ entry -100m (Some groceries); entry 30m (Some groceries) ]

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ Some groceries.Id, 70m ]
                    "spending should be net of the refund"

                Expect.isEmpty statement.IncomeLines "a refund is not income"
                Expect.equal statement.Expenses 70m "expenses should be net of the refund"
                Expect.equal statement.NetIncome -70m "net income should be income minus expenses"
            }

            test "an expense tag with more refunds than spending is a negative expense" {
                let electronics = tag "Electronics" Expense
                let groceries = tag "Groceries" Expense

                let statement =
                    IncomeStatement.compute period [ entry 500m (Some electronics); entry -200m (Some groceries) ]

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ Some groceries.Id, 200m; Some electronics.Id, -500m ]
                    "the returned laptop should stay on the expense side as a negative line"

                Expect.equal statement.Expenses -300m "expenses should be the sum of the lines"
                Expect.equal statement.NetIncome 300m "net income should be income minus expenses"
            }

            test "a clawback reduces its income tag" {
                let salary = tag "Salary" Income

                let statement =
                    IncomeStatement.compute period [ entry 5000m (Some salary); entry -250m (Some salary) ]

                Expect.equal
                    (lineAmounts statement.IncomeLines)
                    [ Some salary.Id, 4750m ]
                    "income should be net of the clawback"

                Expect.isEmpty statement.ExpenseLines "a clawback is not an expense"
                Expect.equal statement.Income 4750m "income should be net of the clawback"
            }

            test "untagged transactions are split by sign and counted" {
                let salary = tag "Salary" Income
                let rent = tag "Rent" Expense

                let statement =
                    IncomeStatement.compute period [
                        entry 5000m (Some salary)
                        entry -2000m (Some rent)
                        entry 40m None
                        entry 10m None
                        entry -25m None
                    ]

                Expect.equal
                    (lineAmounts statement.IncomeLines)
                    [ Some salary.Id, 5000m; None, 50m ]
                    "untagged inflows should be an income line, after the tagged lines"

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ Some rent.Id, 2000m; None, 25m ]
                    "untagged outflows should be an expense line, after the tagged lines"

                Expect.equal statement.Income 5050m "income should include untagged income"
                Expect.equal statement.Expenses 2025m "expenses should include untagged expenses"
                Expect.equal statement.NetIncome 3025m "net income should be income minus expenses"
                Expect.equal statement.UntaggedCount 3 "every untagged transaction should be counted"
            }

            test "lines are sorted largest first with the untagged line last" {
                let rent = tag "Rent" Expense
                let groceries = tag "Groceries" Expense
                let fuel = tag "Fuel" Expense

                let statement =
                    IncomeStatement.compute period [
                        entry -1000m None
                        entry -80m (Some fuel)
                        entry -2000m (Some rent)
                        entry -300m (Some groceries)
                    ]

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ Some rent.Id, 2000m; Some groceries.Id, 300m; Some fuel.Id, 80m; None, 1000m ]
                    "lines should be ordered by amount, with the untagged line last"
            }

            test "each expense line carries its share of total expenses" {
                let rent = tag "Rent" Expense
                let groceries = tag "Groceries" Expense

                let statement =
                    IncomeStatement.compute period [ entry -750m (Some rent); entry -250m (Some groceries) ]

                Expect.equal
                    (statement.ExpenseLines |> List.map (fun line -> line.Share))
                    [ Some 75m; Some 25m ]
                    "shares should be percentages of total expenses"
            }

            test "shares are rounded to two decimal places" {
                let a = tag "A" Expense
                let b = tag "B" Expense
                let c = tag "C" Expense

                let statement =
                    IncomeStatement.compute period [ entry -10m (Some a); entry -10m (Some b); entry -10m (Some c) ]

                Expect.equal
                    (statement.ExpenseLines |> List.map (fun line -> line.Share))
                    [ Some 33.33m; Some 33.33m; Some 33.33m ]
                    "a third should round to 33.33%"
            }

            test "a negative expense line has a negative share" {
                let rent = tag "Rent" Expense
                let electronics = tag "Electronics" Expense

                let statement =
                    IncomeStatement.compute period [ entry -1000m (Some rent); entry 200m (Some electronics) ]

                Expect.equal
                    (statement.ExpenseLines |> List.map (fun line -> line.Share))
                    [ Some 125m; Some -25m ]
                    "shares should be relative to net expenses"
            }

            test "shares are omitted when total expenses are not positive" {
                let electronics = tag "Electronics" Expense

                let statement = IncomeStatement.compute period [ entry 200m (Some electronics) ]

                Expect.equal
                    (statement.ExpenseLines |> List.map (fun line -> line.Share))
                    [ None ]
                    "a share of a non-positive total is meaningless"
            }
        ]

module PeriodTests =
    open System
    open Expecto

    open Budgeteur.Feature.IncomeStatement

    [<Tests>]
    let tests =
        testList "Period.create" [
            test "a single day is a valid period" {
                let day = DateOnly (2026, 10, 10)
                Expect.isOk (Period.create day day) "from = to should be valid"
            }

            test "from after to is rejected" {
                Expect.isError
                    (Period.create (DateOnly (2026, 10, 2)) (DateOnly (2026, 10, 1)))
                    "from > to should be rejected"
            }

            test "a leap year is the longest valid period" {
                Expect.isOk (Period.create (DateOnly (2028, 1, 1)) (DateOnly (2028, 12, 31))) "366 days should be valid"

                Expect.isError
                    (Period.create (DateOnly (2028, 1, 1)) (DateOnly (2029, 1, 1)))
                    "367 days should be rejected"
            }
        ]
