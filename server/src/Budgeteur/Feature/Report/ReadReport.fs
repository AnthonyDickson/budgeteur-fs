namespace Budgeteur.Feature.Report

open System

open Budgeteur.Domain.Account
open Budgeteur.Domain.BalanceSheet
open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.IncomeStatement
open Budgeteur.Domain.ReportingPeriod
open Budgeteur.Domain.Side
open Budgeteur.Domain.Tag
open Budgeteur.Domain.Term
open Budgeteur.Shared.OpenApi

/// <summary>Net worth and working capital on one date.</summary>
type PositionResponse = {
    /// <summary>Total assets minus total liabilities.</summary>
    NetWorth : decimal

    /// <summary>Current assets minus current liabilities.</summary>
    WorkingCapital : decimal
}

/// <summary>A line on the closing balance sheet: an item or an account with a
/// known balance.</summary>
type ReportSheetLineResponse = {
    /// <summary>The item's or account's id.</summary>
    Id : Guid

    Name : string

    /// <summary>For an account, from the sign of its balance.</summary>
    [<SchemaHint.Enum(typeof<Side>)>]
    Side : string

    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The magnitude of the line's value or balance. Direction is
    /// implied by Side.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Amount : decimal

    /// <summary>The date of the observation the amount comes from.</summary>
    AsOf : DateOnly
}

/// <summary>The balance sheet at the end of the report's period.</summary>
type ReportSheetResponse = {
    /// <summary>Total value of everything owned.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    TotalAssets : decimal

    /// <summary>Total value of everything owed.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    TotalLiabilities : decimal

    NetWorth : decimal
    WorkingCapital : decimal

    /// <summary>Items, then accounts with a known balance.</summary>
    Lines : ReportSheetLineResponse list

    /// <summary>The names of accounts without any balance, left out of the
    /// totals.</summary>
    UnknownBalances : string list
}

/// <summary>One tag's net amount for the period, or the untagged income or
/// untagged expenses.</summary>
type ReportLineResponse = {
    /// <summary>The tag, or none for an untagged line.</summary>
    TagId : Guid option

    /// <summary>The tag's name, or "Untagged income" or "Untagged
    /// expenses".</summary>
    Name : string

    /// <summary>The tag's hex color, or none for an untagged line.</summary>
    Color : string option

    Amount : decimal

    /// <summary>An expense line's percentage of total expenses. None for income
    /// lines, and when total expenses are zero or negative.</summary>
    Share : decimal option
}

/// <summary>The position and performance for one reporting period. See
/// docs/reports.md.</summary>
type ReportResponse = {
    [<SchemaHint.Enum(typeof<Frequency>)>]
    Frequency : string

    /// <summary>The period's name, e.g. "March 2026", "Q1 2026", "2026", or
    /// "2026/27".</summary>
    Label : string

    /// <summary>The period's first day.</summary>
    From : DateOnly

    /// <summary>The period's last day.</summary>
    To : DateOnly

    /// <summary>The closing balance sheet's statement date, and the last day
    /// of the income statement: the period's last day, or the client's today
    /// for a report to date.</summary>
    ClosingDate : DateOnly

    /// <summary>False for a report to date.</summary>
    Complete : bool

    /// <summary>Whether the period before has a report.</summary>
    HasPrevious : bool

    /// <summary>Whether the period after has a report.</summary>
    HasNext : bool

    /// <summary>The position the day before the period starts.</summary>
    Opening : PositionResponse

    Closing : ReportSheetResponse

    /// <summary>Closing net worth minus opening net worth. None when the
    /// opening balance sheet has no lines, where it is not
    /// meaningful.</summary>
    ChangeInNetWorth : decimal option

    /// <summary>The change in net worth minus net income: revaluations, money
    /// that never passes through a tracked account, and missing transactions.
    /// None when the change is.</summary>
    OtherChanges : decimal option

    Income : decimal
    Expenses : decimal
    NetIncome : decimal

    /// <summary>Net income as a percentage of income. None when income is
    /// zero or negative.</summary>
    SavingsRate : decimal option

    IncomeLines : ReportLineResponse list
    ExpenseLines : ReportLineResponse list
}

module ReportResponse =
    let private position (sheet : BalanceSheet) : PositionResponse = {
        NetWorth = BalanceSheet.netWorth sheet
        WorkingCapital = BalanceSheet.workingCapital sheet
    }

    let private sheet (sheet : BalanceSheet) : ReportSheetResponse =
        let items =
            sheet.Items
            |> List.map (fun item -> {
                Id = item.Item.Id
                Name = ItemName.value item.Item.Name
                Side = Side.toString item.Item.Side
                Term = Term.toString item.Item.Term
                Amount = Value.value item.Current.Value
                AsOf = item.Current.AsOf
            })

        let accounts =
            sheet.Accounts
            |> List.choose (fun account ->
                account.Current
                |> Option.map (fun current ->
                    let side, amount =
                        BalanceSheet.accountSide current.Balance

                    {
                        Id = account.Account.Id
                        Name = AccountName.value account.Account.Name
                        Side = Side.toString side
                        Term = Term.toString account.Account.Term
                        Amount = amount
                        AsOf = current.AsOf
                    }))

        {
            TotalAssets = BalanceSheet.totalAssets sheet
            TotalLiabilities = BalanceSheet.totalLiabilities sheet
            NetWorth = BalanceSheet.netWorth sheet
            WorkingCapital = BalanceSheet.workingCapital sheet
            Lines = items @ accounts
            UnknownBalances =
                BalanceSheet.unknownBalances sheet
                |> List.map (fun account -> AccountName.value account.Name)
        }

    let private line
        (untaggedName : string)
        (tag : Tag option)
        (amount : decimal)
        (share : decimal option)
        : ReportLineResponse = {
        TagId = tag |> Option.map _.Id
        Name =
            tag
            |> Option.map (fun tag -> TagName.value tag.Name)
            |> Option.defaultValue untaggedName
        Color = tag |> Option.map (fun tag -> TagColor.value tag.Color)
        Amount = amount
        Share = share
    }

    let fromDomain (report : Report) : ReportResponse =
        let statement = report.IncomeStatement

        {
            Frequency =
                Frequency.toString (ReportingPeriod.frequency report.Period)
            Label = ReportingPeriod.label report.Period
            From = ReportingPeriod.fromDate report.Period
            To = ReportingPeriod.toDate report.Period
            ClosingDate = report.ClosingDate
            Complete = report.Complete
            HasPrevious = report.HasPrevious
            HasNext = report.HasNext
            Opening = position report.Opening
            Closing = sheet report.Closing
            ChangeInNetWorth = report.ChangeInNetWorth |> Option.map _.Change
            OtherChanges = report.ChangeInNetWorth |> Option.map _.OtherChanges
            Income = statement.Income
            Expenses = statement.Expenses
            NetIncome = statement.NetIncome
            SavingsRate = report.SavingsRate
            IncomeLines =
                statement.IncomeLines
                |> List.map (fun incomeLine ->
                    line
                        "Untagged income"
                        incomeLine.Tag
                        incomeLine.Amount
                        None)
            ExpenseLines =
                statement.ExpenseLines
                |> List.map (fun expenseLine ->
                    line
                        "Untagged expenses"
                        expenseLine.Tag
                        expenseLine.Amount
                        expenseLine.Share)
        }

module ReadReport =
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
    let Path = "/api/reports"

    /// <summary>What the request asks for: the frequency, the client's today,
    /// and optionally a date in the period.</summary>
    type ReportQuery = {
        Frequency : Frequency
        Today : DateOnly
        Date : DateOnly option
    }

    let private queryParam (ctx : HttpContext) (name : string) =
        match ctx.Request.Query.TryGetValue name with
        | true, values when not (String.IsNullOrWhiteSpace (string values)) ->
            Some (string values)
        | _ -> None

    let private parseDate
        (name : string)
        (value : string)
        : Validation<DateOnly, string> =
        match Extra.DateOnly.tryParse value with
        | Some date -> Ok date
        | None ->
            Error [
                $"The query parameter '{name}' must be a date in the format \
                yyyy-MM-dd, got '{value}'"
            ]

    let private required (name : string) (value : string option) =
        value
        |> Result.requireSome [ $"The query parameter '{name}' is required" ]

    /// <summary>Parse the query parameters, reporting every failure in one
    /// error.</summary>
    let validateQuery
        (frequency : string option)
        (today : string option)
        (date : string option)
        : Result<ReportQuery, DomainError> =
        validation {
            let! frequency =
                required "frequency" frequency
                |> Result.bind (
                    Frequency.parse >> Result.mapError List.singleton
                )

            and! today =
                required "today" today |> Result.bind (parseDate "today")

            and! date = date |> Option.traverseResult (parseDate "date")

            return {
                Frequency = frequency
                Today = today
                Date = date
            }
        }
        |> Result.mapError (String.concat "; " >> ValidationFailed)

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! query =
                    validateQuery
                        (queryParam ctx "frequency")
                        (queryParam ctx "today")
                        (queryParam ctx "date")

                let! history =
                    BalanceSheetHistoryQuery.read queryContext userId

                let! firstTransaction =
                    IncomeStatementQuery.firstTransactionDate
                        queryContext
                        userId

                let range =
                    Report.range
                        query.Frequency
                        query.Today
                        (Report.firstDate history firstTransaction)

                let! period =
                    Report.period range query.Date
                    |> Result.requireSome (
                        NotFound "There is no report for that period"
                    )

                let! entries =
                    IncomeStatementQuery.entries
                        queryContext
                        userId
                        (Report.statementPeriod query.Today period)

                let report =
                    Report.compute query.Today range period history entries

                log.Info (
                    $"Returned the report for %s{ReportingPeriod.label period}",
                    LogProp.prop "period" (ReportingPeriod.label period)
                )

                do! Json.write ctx (ReportResponse.fromDomain report)
            })

    let private parameter
        (name : string)
        (required : bool)
        (description : string)
        (format : string option)
        : IOpenApiParameter =
        OpenApiParameter (
            Name = name,
            In = Nullable ParameterLocation.Query,
            Required = required,
            Description = description,
            Schema =
                OpenApiSchema (
                    Type = Nullable JsonSchemaType.String,
                    Format = Option.toObj format
                )
        )

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get a report"

        op.Description <-
            "Returns the report for the period of a frequency containing a \
            date: its opening and closing positions, change in net worth, and \
            income statement. Without a date, returns the latest complete \
            period. Periods run from the one containing the user's first data \
            to the one containing today; any other date is 404."

        op.Parameters <-
            ResizeArray [
                parameter
                    "frequency"
                    true
                    "Monthly, Quarterly, CalendarYear, or FinancialYear."
                    None
                parameter
                    "today"
                    true
                    "The client's local date, e.g. 2026-10-14."
                    (Some "date")
                parameter
                    "date"
                    false
                    "Any date in the period, e.g. 2026-09-01."
                    (Some "date")
            ]

        op.Tags <- HashSet [ OpenApiTagReference "Reports" ]
        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<ReportResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 404)
                |],
                configureOperation = configureOperation
            )
        )
