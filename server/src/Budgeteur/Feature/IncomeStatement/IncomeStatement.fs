namespace Budgeteur.Feature.IncomeStatement

open System

open Budgeteur.Domain.Tag
open Budgeteur.Shared.Money

/// <summary>An inclusive range of calendar dates, at most <c>Period.MaxDays</c> long.</summary>
type Period = private Period of fromDate : DateOnly * toDate : DateOnly

module Period =
    /// <summary>The longest period, in days: a leap year.</summary>
    [<Literal>]
    let MaxDays = 366

    let create (fromDate : DateOnly) (toDate : DateOnly) : Result<Period, string> =
        let days = toDate.DayNumber - fromDate.DayNumber + 1

        if fromDate > toDate then
            Error $"'from' (%O{fromDate}) must not be after 'to' (%O{toDate})"
        elif days > MaxDays then
            Error $"A period can span at most %i{MaxDays} days, got %i{days}"
        else
            Ok (Period (fromDate, toDate))

    let fromDate (Period (fromDate, _)) = fromDate

    let toDate (Period (_, toDate)) = toDate

/// <summary>A non-transfer transaction in the period, with its tag if it has one.</summary>
type Entry = { Amount : decimal; Tag : Tag option }

/// <summary>One tag's net amount for the period, or the untagged income or untagged expenses
/// (<c>Tag = None</c>). Income lines are amounts received; expense lines are amounts spent.</summary>
type Line = { Tag : Tag option; Amount : decimal }

/// <summary>An expense line and its share of total expenses, as a percentage. The share is
/// <c>None</c> when total expenses are zero or negative.</summary>
type ExpenseLine = {
    Tag : Tag option
    Amount : decimal
    Share : decimal option
}

/// <summary>Income, expenses, and net income for a period. See docs/dashboard.md.</summary>
type IncomeStatement = {
    Period : Period
    Income : decimal
    Expenses : decimal
    NetIncome : decimal
    IncomeLines : Line list
    ExpenseLines : ExpenseLine list
    UntaggedCount : int
}

module IncomeStatement =
    /// <summary>Largest amount first, with the untagged line last. Ties are broken by name so the
    /// order is stable.</summary>
    let private sortLines (lines : Line list) =
        lines
        |> List.sortBy (fun line ->
            Option.isNone line.Tag,
            -line.Amount,
            line.Tag
            |> Option.map (fun tag -> TagName.value tag.Name)
            |> Option.defaultValue "")

    /// <summary>The untagged line for one side, or nothing when no untagged transaction is on that
    /// side. <c>sign</c> turns the summed amounts into the side's direction.</summary>
    let private untaggedLine (amounts : decimal list) (sign : decimal) =
        match amounts with
        | [] -> []
        | amounts -> [
            {
                Line.Tag = None
                Amount = sign * List.sum amounts
            }
          ]

    /// <summary>
    /// Build the income statement from the period's non-transfer transactions.
    /// </summary>
    /// <remarks>
    /// Each tag's transactions are netted, and the tag's kind decides the side whatever the sign of
    /// the net: a refund reduces its expense tag (possibly below zero) rather than counting as
    /// income. Untagged transactions have no kind, so they are split by sign into untagged income
    /// and untagged expenses.
    /// </remarks>
    let compute (period : Period) (entries : Entry list) : IncomeStatement =
        let tagNets =
            entries
            |> List.choose (fun entry -> entry.Tag |> Option.map (fun tag -> tag, entry.Amount))
            |> List.groupBy fst
            |> List.map (fun (tag, group) -> tag, Money.roundToCents (List.sumBy snd group))

        let untagged =
            entries
            |> List.filter (fun entry -> Option.isNone entry.Tag)
            |> List.map (fun entry -> entry.Amount)

        let incomeLines =
            [
                for tag, net in tagNets do
                    if tag.Kind = Income then
                        { Line.Tag = Some tag; Amount = net }
            ]
            @ untaggedLine (List.filter (fun amount -> amount > 0m) untagged) 1m
            |> sortLines

        let expenseLines =
            [
                for tag, net in tagNets do
                    if tag.Kind = Expense then
                        { Line.Tag = Some tag; Amount = -net }
            ]
            @ untaggedLine (List.filter (fun amount -> amount < 0m) untagged) -1m
            |> sortLines

        let income = incomeLines |> List.sumBy (fun (line : Line) -> line.Amount)
        let expenses = expenseLines |> List.sumBy (fun (line : Line) -> line.Amount)

        let share (amount : decimal) =
            if expenses > 0m then
                Some (Decimal.Round (amount / expenses * 100m, 2, MidpointRounding.AwayFromZero))
            else
                None

        {
            Period = period
            Income = income
            Expenses = expenses
            NetIncome = income - expenses
            IncomeLines = incomeLines
            ExpenseLines =
                expenseLines
                |> List.map (fun (line : Line) -> {
                    Tag = line.Tag
                    Amount = line.Amount
                    Share = share line.Amount
                })
            UntaggedCount = List.length untagged
        }
