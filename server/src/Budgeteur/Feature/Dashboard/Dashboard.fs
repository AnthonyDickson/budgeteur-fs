namespace Budgeteur.Feature.Dashboard

open System

open Budgeteur.Domain.IncomeStatement
open Budgeteur.Domain.Money
open Budgeteur.Domain.ReportingPeriod
open Budgeteur.Domain.Tag

/// <summary>The periods the dashboard covers, all worked out from the client's
/// today. See decisions 11, 12, and 14 in docs/dashboard.md.</summary>
type DashboardPeriods = {
    Today : DateOnly

    /// <summary>The first of today's month up to today.</summary>
    MonthToDate : Period

    /// <summary>Up to twelve complete months and today's month, oldest first,
    /// starting no earlier than the month of the user's first data.</summary>
    HistoryMonths : ReportingPeriod list

    /// <summary>The history's complete months that start on or after the
    /// user's first transaction, oldest first.</summary>
    BaselineMonths : ReportingPeriod list
}

/// <summary>A figure's baseline and its change from it. See decision 12 in
/// docs/dashboard.md.</summary>
type Comparison = {
    /// <summary>The figure's mean over the same days of the baseline
    /// months.</summary>
    Baseline : decimal

    /// <summary>The figure minus its baseline.</summary>
    Change : decimal

    /// <summary>The change as a percentage of the baseline, or none when the
    /// baseline is zero or negative.</summary>
    ChangePercent : decimal option
}

/// <summary>A total for the month to date, with its comparison once there
/// are baseline months.</summary>
type Figure = {
    Amount : decimal
    Comparison : Comparison option
}

/// <summary>One line of the month to date: a tag's net amount, or the
/// untagged income or expenses. A tag with nothing this month but an amount
/// in the baseline is a line with a zero amount.</summary>
type MonthLine = {
    Tag : Tag option
    Amount : decimal

    /// <summary>An expense line's percentage of the month's expenses. None
    /// for income lines, and when expenses are zero or negative.</summary>
    Share : decimal option

    Comparison : Comparison option
}

/// <summary>The month to date against its baseline.</summary>
type MonthFigures = {
    Period : Period
    Income : Figure
    Expenses : Figure
    NetIncome : Figure
    SavingsRate : decimal option

    /// <summary>The savings rate of the baseline income and net income. None
    /// with no baseline months, or when the baseline income is zero or
    /// negative.</summary>
    SavingsRateBaseline : decimal option

    /// <summary>The savings rate minus its baseline, in percentage
    /// points.</summary>
    SavingsRateChange : decimal option

    /// <summary>Largest first, with the untagged line last.</summary>
    IncomeLines : MonthLine list

    /// <summary>Largest first, with the untagged line last.</summary>
    ExpenseLines : MonthLine list

    /// <summary>How many months the baselines are the mean of. Zero while the
    /// baseline is still building, when no figure has a comparison.</summary>
    BaselineMonthCount : int

    /// <summary>The date of the month's latest transaction, if any.</summary>
    LatestTransaction : DateOnly option
}

module Dashboard =
    /// <summary>How many complete months the history covers at most.</summary>
    [<Literal>]
    let HistoryMonthCount = 12

    let private period (fromDate : DateOnly) (toDate : DateOnly) : Period =
        match Period.create fromDate toDate with
        | Ok period -> period
        // Unreachable: every dashboard period is within thirteen months
        | Error error -> failwith error

    /// <summary>The closing date of a history month: its last day once it is
    /// complete, otherwise today.</summary>
    let closingDate (today : DateOnly) (month : ReportingPeriod) =
        if ReportingPeriod.isComplete today month then
            ReportingPeriod.toDate month
        else
            today

    /// <summary>A month's first day to its closing date.</summary>
    let monthPeriod (today : DateOnly) (month : ReportingPeriod) : Period =
        period (ReportingPeriod.fromDate month) (closingDate today month)

    /// <summary>
    /// The days of a baseline month that match the month to date: from its
    /// first day to today's day of the month.
    /// </summary>
    /// <remarks>
    /// The day is clamped to the month's length, and on the last day of
    /// today's month the whole baseline month is used: on 30 March the
    /// February days are 1 to 28, and on 30 September the whole of August.
    /// </remarks>
    let sameDays (today : DateOnly) (month : ReportingPeriod) : Period =
        let current = ReportingPeriod.containing Monthly today
        let fromDate = ReportingPeriod.fromDate month
        let lastDay = ReportingPeriod.toDate month

        let toDate =
            if today = ReportingPeriod.toDate current then
                lastDay
            else
                min (fromDate.AddDays (today.Day - 1)) lastDay

        period fromDate toDate

    /// <summary>The dashboard's periods for the client's today, given the
    /// user's first data date (observation or transaction) and first
    /// transaction date.</summary>
    let periods
        (today : DateOnly)
        (firstData : DateOnly option)
        (firstTransaction : DateOnly option)
        : DashboardPeriods =
        let current = ReportingPeriod.containing Monthly today

        let earliest =
            ReportingPeriod.fromDate(current).AddMonths -HistoryMonthCount

        // A user with no data has today's month only, as on the reports page
        let first =
            match firstData with
            | Some firstData ->
                max earliest (min firstData today)
                |> ReportingPeriod.containing Monthly
            | None -> current

        let historyMonths =
            List.unfold
                (fun month ->
                    if ReportingPeriod.fromDate month > today then
                        None
                    else
                        Some (month, ReportingPeriod.next month))
                first

        let baselineMonths =
            match firstTransaction with
            | Some firstTransaction ->
                historyMonths
                |> List.filter (fun month ->
                    ReportingPeriod.isComplete today month
                    && ReportingPeriod.fromDate month >= firstTransaction)
            | None -> []

        {
            Today = today
            MonthToDate = monthPeriod today current
            HistoryMonths = historyMonths
            BaselineMonths = baselineMonths
        }

    /// <summary>The one span the dashboard's transactions are read for: the
    /// first history month's first day up to today.</summary>
    let readPeriod (periods : DashboardPeriods) : Period =
        let first =
            periods.HistoryMonths
            |> List.tryHead
            |> Option.map ReportingPeriod.fromDate
            |> Option.defaultValue (Period.fromDate periods.MonthToDate)

        period first periods.Today

    /// <summary>The entries dated within the period.</summary>
    let entriesIn (period : Period) (entries : Entry list) =
        entries
        |> List.filter (fun entry ->
            entry.Date >= Period.fromDate period
            && entry.Date <= Period.toDate period)

    /// <summary>A part as a percentage of a positive whole, rounded to two
    /// decimal places.</summary>
    let private percentOf (whole : decimal) (part : decimal) =
        if whole > 0m then
            Some (
                Decimal.Round (
                    part / whole * 100m,
                    2,
                    MidpointRounding.AwayFromZero
                )
            )
        else
            None

    let private comparison (amount : decimal) (baseline : decimal) = {
        Baseline = baseline
        Change = amount - baseline
        ChangePercent = percentOf baseline (amount - baseline)
    }

    /// <summary>Largest amount first, with the untagged line last. Ties are
    /// broken by name so the order is stable.</summary>
    let private sortLines (lines : MonthLine list) =
        lines
        |> List.sortBy (fun line ->
            Option.isNone line.Tag,
            -line.Amount,
            line.Tag
            |> Option.map (fun tag -> TagName.value tag.Name)
            |> Option.defaultValue "")

    /// <summary>Each income line's tag, amount, and no share.</summary>
    let private incomeSide (statement : IncomeStatement) =
        statement.IncomeLines
        |> List.map (fun line -> line.Tag, line.Amount, None)

    /// <summary>Each expense line's tag, amount, and share.</summary>
    let private expenseSide (statement : IncomeStatement) =
        statement.ExpenseLines
        |> List.map (fun line -> line.Tag, line.Amount, line.Share)

    /// <summary>
    /// One side's lines: the month's, plus a zero line for each tag in the
    /// baseline with nothing this month, each compared with its mean over the
    /// baseline statements.
    /// </summary>
    let private lines
        (side : IncomeStatement -> (Tag option * decimal * decimal option) list)
        (statement : IncomeStatement)
        (baselines : IncomeStatement list)
        (zeroShare : decimal option)
        : MonthLine list =
        let monthLines = side statement
        let months = List.length baselines

        let baselineLines =
            baselines
            |> List.collect side
            |> List.map (fun (tag, amount, _) -> tag, amount)

        let baselineOf (tag : Tag option) =
            if months = 0 then
                None
            else
                let total =
                    baselineLines
                    |> List.filter (fun (lineTag, _) -> lineTag = tag)
                    |> List.sumBy snd

                Some (Money.roundToCents (total / decimal months))

        let monthTags = monthLines |> List.map (fun (tag, _, _) -> tag)

        let zeroLines =
            baselineLines
            |> List.map fst
            |> List.distinct
            |> List.filter (fun tag -> not (List.contains tag monthTags))
            |> List.map (fun tag -> tag, 0m, zeroShare)

        monthLines @ zeroLines
        |> List.map (fun (tag, amount, share) -> {
            Tag = tag
            Amount = amount
            Share = share
            Comparison = baselineOf tag |> Option.map (comparison amount)
        })
        |> sortLines

    /// <summary>
    /// The month to date's income statement against its baseline: the mean
    /// of each total and line over the same days of each baseline month. See
    /// decisions 12 and 13 in docs/dashboard.md.
    /// </summary>
    /// <remarks>
    /// The savings rate's baseline is the rate of the baseline means, not the
    /// mean of each month's rate, so a month with little income does not
    /// swing it.
    /// </remarks>
    let month
        (periods : DashboardPeriods)
        (entries : Entry list)
        : MonthFigures =
        let statementFor (period : Period) =
            IncomeStatement.compute period (entriesIn period entries)

        let statement = statementFor periods.MonthToDate

        let baselines =
            periods.BaselineMonths
            |> List.map (sameDays periods.Today >> statementFor)

        let months = List.length baselines

        let mean (figure : IncomeStatement -> decimal) =
            if months = 0 then
                None
            else
                Some (
                    Money.roundToCents (
                        List.sumBy figure baselines / decimal months
                    )
                )

        let figure (amount : decimal) (baseline : decimal option) = {
            Amount = amount
            Comparison = baseline |> Option.map (comparison amount)
        }

        let income = mean _.Income
        let netIncome = mean _.NetIncome
        let savingsRate = IncomeStatement.savingsRate statement

        let savingsRateBaseline =
            Option.map2 percentOf income netIncome |> Option.flatten

        {
            Period = periods.MonthToDate
            Income = figure statement.Income income
            Expenses = figure statement.Expenses (mean _.Expenses)
            NetIncome = figure statement.NetIncome netIncome
            SavingsRate = savingsRate
            SavingsRateBaseline = savingsRateBaseline
            SavingsRateChange = Option.map2 (-) savingsRate savingsRateBaseline
            IncomeLines = lines incomeSide statement baselines None
            ExpenseLines =
                lines
                    expenseSide
                    statement
                    baselines
                    (percentOf statement.Expenses 0m)
            BaselineMonthCount = months
            LatestTransaction =
                match entriesIn periods.MonthToDate entries with
                | [] -> None
                | entries -> Some (entries |> List.map _.Date |> List.max)
        }
