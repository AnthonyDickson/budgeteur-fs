namespace Budgeteur.Feature.Dashboard

open System

open Budgeteur.Domain.IncomeStatement
open Budgeteur.Domain.ReportingPeriod

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
