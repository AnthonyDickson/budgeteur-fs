namespace Budgeteur.Feature.Report

open System

open Budgeteur.Domain.Account
open Budgeteur.Domain.BalanceSheet
open Budgeteur.Domain.IncomeStatement
open Budgeteur.Domain.ReportingPeriod

/// <summary>How net worth changed over a report's period, and how much of
/// that was saved.</summary>
type ChangeInNetWorth = {
    /// <summary>Closing net worth minus opening net worth.</summary>
    Change : decimal

    /// <summary>The change net income does not explain: revaluations, money
    /// that never passes through a tracked account, and missing
    /// transactions.</summary>
    OtherChanges : decimal
}

/// <summary>The periods of a frequency that have reports: from the one
/// containing the user's first observation or transaction to the one
/// containing today. See decision 5 in docs/reports.md.</summary>
type ReportRange = {
    First : ReportingPeriod

    /// <summary>The period containing today, which is to date.</summary>
    Current : ReportingPeriod
}

/// <summary>The position and performance for one reporting period. See
/// docs/reports.md.</summary>
type Report = {
    Period : ReportingPeriod

    /// <summary>The closing balance sheet's statement date: the period's last
    /// day, or the client's today for a report to date.</summary>
    ClosingDate : DateOnly

    Complete : bool
    Opening : BalanceSheet
    Closing : BalanceSheet

    /// <summary>None when the opening balance sheet has no lines, since the
    /// change would be the whole closing net worth: not meaningful.</summary>
    ChangeInNetWorth : ChangeInNetWorth option

    IncomeStatement : IncomeStatement
    SavingsRate : decimal option
    HasPrevious : bool
    HasNext : bool
}

module Report =
    /// <summary>The periods of the frequency that have reports, given the
    /// user's first data date. A user with no data has today's period
    /// only.</summary>
    let range
        (frequency : Frequency)
        (today : DateOnly)
        (firstDate : DateOnly option)
        : ReportRange =
        let first =
            firstDate
            |> Option.map (min today)
            |> Option.defaultValue today
            |> ReportingPeriod.containing frequency

        {
            First = first
            Current = ReportingPeriod.containing frequency today
        }

    let private isInRange (range : ReportRange) (period : ReportingPeriod) =
        ReportingPeriod.fromDate period >= ReportingPeriod.fromDate range.First
        && ReportingPeriod.fromDate period
           <= ReportingPeriod.fromDate range.Current

    /// <summary>The period to report on: the one containing <c>date</c>, or
    /// with no date the latest complete period, falling back to the period
    /// to date when no complete one has data. None when the date is outside
    /// the range.</summary>
    let period
        (range : ReportRange)
        (date : DateOnly option)
        : ReportingPeriod option =
        match date with
        | Some date ->
            Some (
                ReportingPeriod.containing
                    (ReportingPeriod.frequency range.Current)
                    date
            )
            |> Option.filter (isInRange range)
        | None ->
            let previous = ReportingPeriod.previous range.Current

            if isInRange range previous then
                Some previous
            else
                Some range.Current

    /// <summary>The earliest date the user has data for: their first
    /// observation or first transaction, whichever is earlier.</summary>
    let firstDate
        (history : BalanceSheetHistory)
        (firstTransaction : DateOnly option)
        : DateOnly option =
        let observations =
            (history.ItemHistories
             |> List.collect (fun (_, observations) ->
                 observations |> List.map _.AsOf))
            @ (history.AccountHistories
               |> List.collect (fun (_, observations) ->
                   observations
                   |> List.map (fun (observation : BalanceObservation) ->
                       observation.AsOf)))

        match Option.toList firstTransaction @ observations with
        | [] -> None
        | dates -> Some (List.min dates)

    /// <summary>The closing balance sheet's statement date: the period's last
    /// day once it is complete, otherwise the client's today. The income
    /// statement runs to the same date.</summary>
    let closingDate (today : DateOnly) (period : ReportingPeriod) =
        if ReportingPeriod.isComplete today period then
            ReportingPeriod.toDate period
        else
            today

    /// <summary>The income statement period: the period's first day to the
    /// closing date.</summary>
    let statementPeriod (today : DateOnly) (period : ReportingPeriod) : Period =
        match
            Period.create
                (ReportingPeriod.fromDate period)
                (closingDate today period)
        with
        | Ok statementPeriod -> statementPeriod
        // Unreachable: the closing date is within a period of at most a year
        | Error error -> failwith error

    /// <summary>Whether a balance sheet has any line with a known
    /// balance.</summary>
    let private hasLines (sheet : BalanceSheet) =
        not (List.isEmpty sheet.Items)
        || sheet.Accounts |> List.exists (fun account -> account.Current.IsSome)

    /// <summary>
    /// Compute the report for a period from the user's balance sheet history
    /// and the period's income statement entries, which run from the period's
    /// first day to the closing date. The period is one of the range.
    /// </summary>
    let compute
        (today : DateOnly)
        (range : ReportRange)
        (period : ReportingPeriod)
        (history : BalanceSheetHistory)
        (entries : Entry list)
        : Report =
        let closingDate = closingDate today period

        let opening =
            BalanceSheet.asOf
                ((ReportingPeriod.fromDate period).AddDays -1)
                history

        let closing = BalanceSheet.asOf closingDate history

        let statement =
            IncomeStatement.compute (statementPeriod today period) entries

        let changeInNetWorth =
            if hasLines opening then
                let change =
                    BalanceSheet.netWorth closing
                    - BalanceSheet.netWorth opening

                Some {
                    Change = change
                    OtherChanges = change - statement.NetIncome
                }
            else
                None

        {
            Period = period
            ClosingDate = closingDate
            Complete = ReportingPeriod.isComplete today period
            Opening = opening
            Closing = closing
            ChangeInNetWorth = changeInNetWorth
            IncomeStatement = statement
            SavingsRate = IncomeStatement.savingsRate statement
            HasPrevious = period <> range.First
            HasNext = period <> range.Current
        }
