namespace Budgeteur.Feature.IncomeStatement

open System

open Budgeteur.Domain.Tag
open Budgeteur.Shared.OpenApi

/// <summary>One tag's net amount for the period, or the untagged
/// income.</summary>
type IncomeLineResponse = {
    /// <summary>The tag, or none for the untagged line.</summary>
    TagId : Guid option

    /// <summary>The tag's name, or "Untagged income".</summary>
    Name : string

    /// <summary>The tag's hex color, or none for the untagged line.</summary>
    Color : string option

    /// <summary>The amount received. Negative when clawbacks exceed
    /// income.</summary>
    Amount : decimal
}

/// <summary>One tag's net amount for the period, or the untagged
/// expenses.</summary>
type ExpenseLineResponse = {
    /// <summary>The tag, or none for the untagged line.</summary>
    TagId : Guid option

    /// <summary>The tag's name, or "Untagged expenses".</summary>
    Name : string

    /// <summary>The tag's hex color, or none for the untagged line.</summary>
    Color : string option

    /// <summary>The amount spent. Negative when refunds exceed
    /// spending.</summary>
    Amount : decimal

    /// <summary>The line's percentage of total expenses, e.g. "12.5" for 12.5%.
    /// None when total expenses are zero or negative.</summary>
    Share : decimal option
}

/// <summary>Income, expenses, and net income for an inclusive period of
/// calendar dates.</summary>
type IncomeStatementResponse = {
    /// <summary>The first day of the period.</summary>
    From : DateOnly

    /// <summary>The last day of the period (inclusive).</summary>
    To : DateOnly

    /// <summary>The sum of the income lines.</summary>
    Income : decimal

    /// <summary>The sum of the expense lines.</summary>
    Expenses : decimal

    /// <summary>Income minus expenses.</summary>
    NetIncome : decimal

    /// <summary>Lines for income tags and untagged income, largest first,
    /// untagged last.</summary>
    IncomeLines : IncomeLineResponse list

    /// <summary>Lines for expense tags and untagged expenses, largest first,
    /// untagged last.</summary>
    ExpenseLines : ExpenseLineResponse list

    /// <summary>The number of non-transfer transactions in the period without a
    /// tag.</summary>
    UntaggedCount : int
}

module IncomeStatementResponse =
    let private name (untaggedName : string) (tag : Tag option) =
        tag
        |> Option.map (fun tag -> TagName.value tag.Name)
        |> Option.defaultValue untaggedName

    let private color (tag : Tag option) =
        tag |> Option.map (fun tag -> TagColor.value tag.Color)

    let fromDomain (statement : IncomeStatement) : IncomeStatementResponse = {
        From = Period.fromDate statement.Period
        To = Period.toDate statement.Period
        Income = statement.Income
        Expenses = statement.Expenses
        NetIncome = statement.NetIncome
        IncomeLines =
            statement.IncomeLines
            |> List.map (fun line -> {
                TagId = line.Tag |> Option.map _.Id
                Name = name "Untagged income" line.Tag
                Color = color line.Tag
                Amount = line.Amount
            })
        ExpenseLines =
            statement.ExpenseLines
            |> List.map (fun line -> {
                TagId = line.Tag |> Option.map _.Id
                Name = name "Untagged expenses" line.Tag
                Color = color line.Tag
                Amount = line.Amount
                Share = line.Share
            })
        UntaggedCount = statement.UntaggedCount
    }

module ReadIncomeStatement =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.AspNetCore.Http
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

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
    let Path = "/api/income-statement"

    let private queryParam (ctx : HttpContext) (name : string) =
        match ctx.Request.Query.TryGetValue name with
        | true, values when not (String.IsNullOrWhiteSpace (string values)) ->
            Some (string values)
        | _ -> None

    let private parseDate
        (name : string)
        (value : string option)
        : Validation<DateOnly, string> =
        match value with
        | None -> Error [ $"The query parameter '{name}' is required" ]
        | Some value ->
            match Extra.DateOnly.tryParse value with
            | Some date -> Ok date
            | None ->
                Error [
                    $"The query parameter '{name}' must be a date in the \
                    format yyyy-MM-dd, got '{value}'"
                ]

    /// <summary>Parse the <c>from</c> and <c>to</c> query parameters into a
    /// period, reporting every parse failure in one error.</summary>
    let validatePeriod
        (fromValue : string option)
        (toValue : string option)
        : Result<Period, DomainError> =
        validation {
            let! fromDate = parseDate "from" fromValue
            and! toDate = parseDate "to" toValue
            return fromDate, toDate
        }
        |> Result.bind (fun (fromDate, toDate) ->
            Period.create fromDate toDate |> Result.mapError List.singleton)
        |> Result.mapError (String.concat "; " >> ValidationFailed)

    /// <summary>Load the user's non-transfer transactions in the period, each
    /// with its tag.</summary>
    let private getEntries
        (queryContext : QueryContextFactory)
        (userId : string)
        (period : Period)
        =
        task {
            let fromDate = Period.fromDate period
            let toDate = Period.toDate period

            let! transactions =
                selectTask queryContext {
                    for t in main.Transactions do
                        where (
                            t.UserId = userId
                            && t.Date >= fromDate
                            && t.Date <= toDate
                            && not t.IsTransfer
                        )
                }

            and! tags =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.UserId = userId)
                }

            let tagsById =
                tags
                |> Seq.map (fun row ->
                    let tag = TagCodec.fromRow row
                    tag.Id, tag)
                |> Map.ofSeq

            return
                transactions
                |> Seq.map (fun t -> {
                    Entry.Amount = t.Amount
                    Tag =
                        t.TagId
                        |> Option.bind (fun id -> Map.tryFind id tagsById)
                })
                |> List.ofSeq
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx

                let! period =
                    validatePeriod
                        (queryParam ctx "from")
                        (queryParam ctx "to")

                let! entries = getEntries queryContext userId period

                let statement = IncomeStatement.compute period entries
                let count = List.length entries

                log.Info (
                    $"Returned income statement from %i{count} transactions",
                    LogProp.prop "count" count
                )

                do!
                    Json.write
                        ctx
                        (IncomeStatementResponse.fromDomain statement)
            })

    let private dateParameter
        (name : string)
        (description : string)
        : IOpenApiParameter =
        OpenApiParameter (
            Name = name,
            In = Nullable ParameterLocation.Query,
            Required = true,
            Description = description,
            Schema =
                OpenApiSchema (
                    Type = Nullable JsonSchemaType.String,
                    Format = "date"
                )
        )

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Get income statement"

        op.Description <-
            $"Returns income, expenses, and net income for an inclusive period \
            of at most %i{Period.MaxDays} days. Transfers are excluded."

        op.Parameters <-
            ResizeArray [
                dateParameter
                    "from"
                    "The first day of the period, e.g. 2026-10-01."
                dateParameter
                    "to"
                    "The last day of the period (inclusive), e.g. 2026-10-31."
            ]

        op.Tags <- HashSet [ OpenApiTagReference "Income Statements" ]
        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<IncomeStatementResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation = configureOperation
            )
        )
