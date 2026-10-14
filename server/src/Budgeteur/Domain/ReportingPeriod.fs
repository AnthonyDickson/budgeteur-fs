namespace Budgeteur.Domain.ReportingPeriod

open System
open System.Globalization

open Budgeteur.Domain.IncomeStatement

/// <summary>How long a reporting period is. See decision 5 in
/// docs/reports.md.</summary>
type Frequency =
    | Monthly
    /// <summary>Calendar quarters: January to March, and so on. They are also
    /// the quarters of a financial year from 1 April.</summary>
    | Quarterly
    | CalendarYear
    /// <summary>1 April to 31 March.</summary>
    | FinancialYear

module Frequency =
    let toString frequency =
        match frequency with
        | Monthly -> "Monthly"
        | Quarterly -> "Quarterly"
        | CalendarYear -> "CalendarYear"
        | FinancialYear -> "FinancialYear"

    let parse string =
        match string with
        | "Monthly" -> Ok Monthly
        | "Quarterly" -> Ok Quarterly
        | "CalendarYear" -> Ok CalendarYear
        | "FinancialYear" -> Ok FinancialYear
        | other ->
            Error
                $"\"{other}\" is not a valid value for Frequency, expecting \
                one of \"Monthly\", \"Quarterly\", \"CalendarYear\", or \
                \"FinancialYear\"."

/// <summary>A period aligned to a frequency: a calendar month, a quarter, a
/// calendar year, or a financial year. Only <c>containing</c> makes one, so
/// its dates are always aligned.</summary>
type ReportingPeriod = private {
    Frequency : Frequency
    From : DateOnly
    To : DateOnly
}

[<RequireQualifiedAccess>]
module ReportingPeriod =
    /// <summary>The month a financial year starts in.</summary>
    [<Literal>]
    let FinancialYearStart = 4

    /// <summary>The period of the frequency that contains the date.</summary>
    let containing (frequency : Frequency) (date : DateOnly) : ReportingPeriod =
        let monthsFrom (year : int) (month : int) (months : int) =
            let from = DateOnly (year, month, 1)

            {
                Frequency = frequency
                From = from
                To = from.AddMonths(months).AddDays -1
            }

        match frequency with
        | Monthly -> monthsFrom date.Year date.Month 1
        | Quarterly -> monthsFrom date.Year ((date.Month - 1) / 3 * 3 + 1) 3
        | CalendarYear -> monthsFrom date.Year 1 12
        | FinancialYear ->
            let year =
                if date.Month >= FinancialYearStart then
                    date.Year
                else
                    date.Year - 1

            monthsFrom year FinancialYearStart 12

    let frequency (period : ReportingPeriod) = period.Frequency

    let fromDate (period : ReportingPeriod) = period.From

    let toDate (period : ReportingPeriod) = period.To

    /// <summary>The period before, of the same frequency.</summary>
    let previous (period : ReportingPeriod) =
        containing period.Frequency (period.From.AddDays -1)

    /// <summary>The period after, of the same frequency.</summary>
    let next (period : ReportingPeriod) =
        containing period.Frequency (period.To.AddDays 1)

    /// <summary>Whether the period's last day is on or before the client's
    /// <c>today</c>. A report for a period that is not complete is to
    /// date.</summary>
    let isComplete (today : DateOnly) (period : ReportingPeriod) =
        period.To <= today

    /// <summary>The period's name, e.g. "March 2026", "Q1 2026", "2026", or
    /// "2026/27" for the financial year from 1 April 2026.</summary>
    let label (period : ReportingPeriod) =
        let from = period.From

        match period.Frequency with
        | Monthly -> from.ToString ("MMMM yyyy", CultureInfo.InvariantCulture)
        | Quarterly -> $"Q%i{(from.Month - 1) / 3 + 1} %i{from.Year}"
        | CalendarYear -> $"%i{from.Year}"
        | FinancialYear -> $"%i{from.Year}/%02i{(from.Year + 1) % 100}"

    /// <summary>The period as an income statement period. Every reporting
    /// period is at most a year, so it is always a valid one.</summary>
    let toPeriod (period : ReportingPeriod) : Period =
        match Period.create period.From period.To with
        | Ok period -> period
        // Unreachable: a reporting period is at most 366 days
        | Error error -> failwith error
