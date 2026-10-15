namespace Budgeteur.Feature.Dashboard

open System

open Budgeteur.Domain.IncomeStatement
open Budgeteur.Domain.ReportingPeriod
open Budgeteur.Domain.Tag

/// <summary>Where the user stands today.</summary>
type DashboardPositionResponse = {
    /// <summary>Whether the balance sheet has no items or accounts.</summary>
    IsEmpty : bool

    /// <summary>Total assets minus total liabilities.</summary>
    NetWorth : decimal

    /// <summary>Current assets minus current liabilities.</summary>
    WorkingCapital : decimal

    /// <summary>Working capital in months of average expenses, to one decimal
    /// place. Zero when working capital is negative. None when there are no
    /// baseline months or their average expenses are zero or
    /// negative.</summary>
    Runway : decimal option

    /// <summary>The earliest as-of date among the balance sheet's lines with
    /// a known balance.</summary>
    OldestAsOf : DateOnly option
}

/// <summary>A total for the month to date against its baseline. The
/// baseline fields are none while there are no baseline months.</summary>
type FigureResponse = {
    Amount : decimal

    /// <summary>The mean over the same days of the baseline months.</summary>
    Baseline : decimal option

    /// <summary>The amount minus its baseline.</summary>
    Change : decimal option

    /// <summary>The change as a percentage of the baseline. None also when
    /// the baseline is zero or negative.</summary>
    ChangePercent : decimal option
}

/// <summary>One tag's net amount for the month to date, or the untagged
/// income or expenses, against its baseline.</summary>
type MonthLineResponse = {
    /// <summary>The tag, or none for an untagged line.</summary>
    TagId : Guid option

    /// <summary>The tag's name, or "Untagged income" or "Untagged
    /// expenses".</summary>
    Name : string

    /// <summary>The tag's colour, a Catppuccin accent name, or none for an
    /// untagged line.</summary>
    Color : string option

    /// <summary>Zero for a tag with nothing this month but an amount in the
    /// baseline.</summary>
    Amount : decimal

    /// <summary>An expense line's percentage of the month's expenses. None
    /// for income lines, and when expenses are zero or negative.</summary>
    Share : decimal option

    Baseline : decimal option
    Change : decimal option
    ChangePercent : decimal option
}

/// <summary>The month to date against its baseline.</summary>
type MonthResponse = {
    /// <summary>The month's name, e.g. "October 2026".</summary>
    Label : string

    /// <summary>The month's first day.</summary>
    From : DateOnly

    /// <summary>The client's today.</summary>
    To : DateOnly

    Income : FigureResponse
    Expenses : FigureResponse
    NetIncome : FigureResponse

    /// <summary>Net income as a percentage of income. None when income is
    /// zero or negative.</summary>
    SavingsRate : decimal option

    /// <summary>The savings rate of the baseline income and net
    /// income.</summary>
    SavingsRateBaseline : decimal option

    /// <summary>The savings rate minus its baseline, in percentage
    /// points.</summary>
    SavingsRateChange : decimal option

    /// <summary>How many months the baselines are the mean of. Zero while the
    /// baseline is still building.</summary>
    BaselineMonthCount : int

    /// <summary>The date of the month's latest transaction.</summary>
    LatestTransaction : DateOnly option

    /// <summary>Largest first, untagged last.</summary>
    IncomeLines : MonthLineResponse list

    /// <summary>Largest first, untagged last.</summary>
    ExpenseLines : MonthLineResponse list
}

/// <summary>One month of the history.</summary>
type HistoryMonthResponse = {
    /// <summary>The month's name, e.g. "October 2026".</summary>
    Label : string

    /// <summary>The month's first day.</summary>
    From : DateOnly

    /// <summary>The month's last day, or the client's today for the month to
    /// date.</summary>
    ClosingDate : DateOnly

    /// <summary>False for the month to date.</summary>
    Complete : bool

    Income : decimal
    Expenses : decimal
    NetIncome : decimal

    /// <summary>Net worth on the closing date. None when no line has a known
    /// balance then.</summary>
    NetWorth : decimal option

    /// <summary>Working capital on the closing date. None when net worth
    /// is.</summary>
    WorkingCapital : decimal option
}

/// <summary>The baseline months' whole-month figures taken
/// together.</summary>
type HistoryTotalsResponse = {
    /// <summary>How many months the totals cover, from one to
    /// twelve.</summary>
    MonthCount : int

    Income : decimal
    Expenses : decimal
    NetIncome : decimal

    /// <summary>Net income over income for the whole span. None when income
    /// is zero or negative.</summary>
    SavingsRate : decimal option

    AverageIncome : decimal

    /// <summary>The figure runway divides by.</summary>
    AverageExpenses : decimal

    AverageNetIncome : decimal
}

/// <summary>Every figure on the dashboard. See docs/dashboard.md.</summary>
type DashboardResponse = {
    Position : DashboardPositionResponse
    Month : MonthResponse

    /// <summary>Up to twelve complete months and the month to date, oldest
    /// first.</summary>
    History : HistoryMonthResponse list

    /// <summary>None while there are no baseline months.</summary>
    Totals : HistoryTotalsResponse option
}

module DashboardResponse =
    let private figure (figure : Figure) : FigureResponse = {
        Amount = figure.Amount
        Baseline = figure.Comparison |> Option.map _.Baseline
        Change = figure.Comparison |> Option.map _.Change
        ChangePercent = figure.Comparison |> Option.bind _.ChangePercent
    }

    let private line
        (untaggedName : string)
        (line : MonthLine)
        : MonthLineResponse = {
        TagId = line.Tag |> Option.map _.Id
        Name =
            line.Tag
            |> Option.map (fun tag -> TagName.value tag.Name)
            |> Option.defaultValue untaggedName
        Color = line.Tag |> Option.map (fun tag -> TagColor.toString tag.Color)
        Amount = line.Amount
        Share = line.Share
        Baseline = line.Comparison |> Option.map _.Baseline
        Change = line.Comparison |> Option.map _.Change
        ChangePercent = line.Comparison |> Option.bind _.ChangePercent
    }

    let fromDomain (figures : DashboardFigures) : DashboardResponse =
        let month = figures.Month
        let position = figures.Position

        let current =
            ReportingPeriod.containing Monthly (Period.toDate month.Period)

        {
            Position = {
                IsEmpty = position.IsEmpty
                NetWorth = position.NetWorth
                WorkingCapital = position.WorkingCapital
                Runway = position.Runway
                OldestAsOf = position.OldestAsOf
            }
            Month = {
                Label = ReportingPeriod.label current
                From = Period.fromDate month.Period
                To = Period.toDate month.Period
                Income = figure month.Income
                Expenses = figure month.Expenses
                NetIncome = figure month.NetIncome
                SavingsRate = month.SavingsRate
                SavingsRateBaseline = month.SavingsRateBaseline
                SavingsRateChange = month.SavingsRateChange
                BaselineMonthCount = month.BaselineMonthCount
                LatestTransaction = month.LatestTransaction
                IncomeLines =
                    month.IncomeLines |> List.map (line "Untagged income")
                ExpenseLines =
                    month.ExpenseLines |> List.map (line "Untagged expenses")
            }
            History =
                figures.History
                |> List.map (fun history -> {
                    Label = ReportingPeriod.label history.Month
                    From = ReportingPeriod.fromDate history.Month
                    ClosingDate = history.ClosingDate
                    Complete = history.Complete
                    Income = history.Income
                    Expenses = history.Expenses
                    NetIncome = history.NetIncome
                    NetWorth = history.NetWorth
                    WorkingCapital = history.WorkingCapital
                })
            Totals =
                figures.Totals
                |> Option.map (fun totals -> {
                    MonthCount = totals.MonthCount
                    Income = totals.Income
                    Expenses = totals.Expenses
                    NetIncome = totals.NetIncome
                    SavingsRate = totals.SavingsRate
                    AverageIncome = totals.AverageIncome
                    AverageExpenses = totals.AverageExpenses
                    AverageNetIncome = totals.AverageNetIncome
                })
        }

module ReadDashboard =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.AspNetCore.Http
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Coders
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/dashboard"

    /// <summary>Parse the <c>today</c> query parameter.</summary>
    let validateToday (today : string option) : Result<DateOnly, DomainError> =
        match today with
        | None ->
            Error (ValidationFailed "The query parameter 'today' is required")
        | Some value ->
            match Extra.DateOnly.tryParse value with
            | Some date -> Ok date
            | None ->
                Error (
                    ValidationFailed
                        $"The query parameter 'today' must be a date in the \
                        format yyyy-MM-dd, got '{value}'"
                )

    let private queryParam (ctx : HttpContext) (name : string) =
        match ctx.Request.Query.TryGetValue name with
        | true, values when not (String.IsNullOrWhiteSpace (string values)) ->
            Some (string values)
        | _ -> None

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! today = validateToday (queryParam ctx "today")

                let! history =
                    BalanceSheetHistoryQuery.read queryContext userId

                and! firstTransaction =
                    IncomeStatementQuery.firstTransactionDate
                        queryContext
                        userId

                let periods =
                    Dashboard.periodsFor today history firstTransaction

                let! entries =
                    IncomeStatementQuery.entries
                        queryContext
                        userId
                        (Dashboard.readPeriod periods)

                let figures = Dashboard.compute periods history entries
                let count = List.length entries

                log.Info (
                    $"Returned the dashboard from %i{count} transactions",
                    LogProp.prop "count" count
                )

                do! Json.write ctx (DashboardResponse.fromDomain figures)
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get the dashboard"

        op.Description <-
            "Returns today's position and runway, the month to date against \
            the same days of up to twelve earlier months, and the history of \
            up to twelve complete months and the month to date with their \
            totals. Transfers are excluded."

        let today : IOpenApiParameter =
            OpenApiParameter (
                Name = "today",
                In = Nullable ParameterLocation.Query,
                Required = true,
                Description = "The client's local date, e.g. 2026-10-14.",
                Schema =
                    OpenApiSchema (
                        Type = Nullable JsonSchemaType.String,
                        Format = "date"
                    )
            )

        op.Parameters <- ResizeArray [ today ]

        op.Tags <- HashSet [ OpenApiTagReference "Dashboard" ]
        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<DashboardResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
