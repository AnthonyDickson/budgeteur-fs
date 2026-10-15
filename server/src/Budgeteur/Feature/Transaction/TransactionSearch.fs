namespace Budgeteur.Feature.Transaction

open System

open Budgeteur.Domain.Money
open Budgeteur.Domain.Rule
open Budgeteur.Shared.OpenApi

/// <summary>A named date range resolved from the client's today, or custom
/// dates. See decision 3 in docs/transaction-search.md.</summary>
[<RequireQualifiedAccess>]
type DatePreset =
    | AnyTime
    | ThisMonth
    | LastMonth
    | ThisYear
    | LastYear
    /// <summary>The financial year from 1 April containing today.</summary>
    | ThisFinancialYear
    | LastFinancialYear
    | Custom

/// <summary>Which account a match has. See decision 4 in
/// docs/transaction-search.md.</summary>
[<RequireQualifiedAccess>]
type AccountCriterion =
    | Any
    | NoAccount
    | Account of accountId : Guid

/// <summary>How a match is categorised. See decision 4 in
/// docs/transaction-search.md.</summary>
[<RequireQualifiedAccess>]
type TagCriterion =
    | Any
    /// <summary>Untagged or dismissed.</summary>
    | WithoutTag
    | Untagged
    | Dismissed
    | Transfer
    | Tag of tagId : Guid

/// <summary>The sign of a match's amount: a credit is positive and a debit
/// negative, so a zero amount matches only <c>Any</c>.</summary>
[<RequireQualifiedAccess>]
type Direction =
    | Any
    | Credit
    | Debit

/// <summary>The criteria of a valid search, with a date preset resolved to its
/// days. A search matches transactions meeting all of them.</summary>
type Search = {
    /// <summary>Text the description contains, under the rule
    /// comparison.</summary>
    Text : RulePattern option

    /// <summary>The first day, inclusive.</summary>
    From : DateOnly option

    /// <summary>The last day, inclusive.</summary>
    To : DateOnly option

    Account : AccountCriterion
    Tag : TagCriterion
    Direction : Direction

    /// <summary>The smallest absolute amount, inclusive.</summary>
    Minimum : Money option

    /// <summary>The largest absolute amount, inclusive.</summary>
    Maximum : Money option
}

/// <summary>Where the next page starts: after the transaction with this date
/// and id, in the order newest first. See decision 6 in
/// docs/transaction-search.md.</summary>
type Cursor = { Date : DateOnly; Id : Guid }

module Cursor =
    open System.Globalization

    open Budgeteur.Shared.Coders
    open Budgeteur.Shared.DomainError

    /// <summary>The cursor as the client holds it. Opaque to the
    /// client.</summary>
    let toString (cursor : Cursor) =
        let date =
            cursor.Date.ToString ("yyyy-MM-dd", CultureInfo.InvariantCulture)

        $"{date}_{cursor.Id:D}"

    /// <summary>Read a cursor made by <c>toString</c>.</summary>
    let parse (value : string) =
        let malformed = Error (ValidationFailed "The cursor is malformed")

        match value.Split '_' with
        | [| date; id |] ->
            match
                Extra.DateOnly.tryParse date, Guid.TryParseExact (id, "D")
            with
            | Some date, (true, id) -> Ok { Date = date; Id = id }
            | _ -> malformed
        | _ -> malformed

/// <summary>The dates criterion.</summary>
type SearchDatesRequest = {
    [<SchemaHint.Enum(typeof<DatePreset>)>]
    Preset : string

    /// <summary>The first day, inclusive. Custom dates only.</summary>
    From : DateOnly option

    /// <summary>The last day, inclusive. Custom dates only.</summary>
    To : DateOnly option
}

/// <summary>The account criterion.</summary>
type SearchAccountRequest = {
    [<SchemaHint.Enum(typeof<AccountCriterion>)>]
    State : string

    /// <summary>The account's id, for the state <c>Account</c> only.</summary>
    Id : Guid option
}

/// <summary>The tag criterion.</summary>
type SearchTagRequest = {
    /// <summary><c>WithoutTag</c> is untagged or dismissed.</summary>
    [<SchemaHint.Enum(typeof<TagCriterion>)>]
    State : string

    /// <summary>The tag's id, for the state <c>Tag</c> only.</summary>
    Id : Guid option
}

/// <summary>The amount criterion: a direction and a range of sizes.</summary>
type SearchAmountRequest = {
    /// <summary><c>Credit</c> is a positive amount and <c>Debit</c> a negative
    /// one.</summary>
    [<SchemaHint.Enum(typeof<Direction>)>]
    Direction : string

    /// <summary>The smallest absolute amount, inclusive.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Minimum : decimal option

    /// <summary>The largest absolute amount, inclusive.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Maximum : decimal option
}

/// <summary>The criteria of a search, combined with AND.</summary>
type SearchCriteriaRequest = {
    /// <summary>Text the description contains, ignoring case. Trimmed and
    /// validated like a rule pattern; blank text sets no criterion.</summary>
    Text : string

    Dates : SearchDatesRequest
    Account : SearchAccountRequest
    Tag : SearchTagRequest
    Amount : SearchAmountRequest
}

/// <summary>Payload for searching transactions.</summary>
type SearchRequest = {
    Criteria : SearchCriteriaRequest

    /// <summary>The client's date, which date presets are resolved
    /// from.</summary>
    Today : DateOnly

    /// <summary>The previous page's cursor, or none for the first
    /// page.</summary>
    Cursor : string option
}

/// <summary>Validates search requests, resolves date presets, and pages
/// matches. See docs/transaction-search.md.</summary>
module TransactionSearch =
    open FsToolkit.ErrorHandling

    open Budgeteur.Domain.ReportingPeriod
    open Budgeteur.Shared.DomainError

    /// <summary>The most matches a page holds.</summary>
    [<Literal>]
    let PageSize = 100

    let private text (value : string) =
        if String.IsNullOrWhiteSpace value then
            Ok None
        else
            RulePattern.create value |> Result.map Some

    let private parsePreset (value : string) =
        match value with
        | "AnyTime" -> Ok DatePreset.AnyTime
        | "ThisMonth" -> Ok DatePreset.ThisMonth
        | "LastMonth" -> Ok DatePreset.LastMonth
        | "ThisYear" -> Ok DatePreset.ThisYear
        | "LastYear" -> Ok DatePreset.LastYear
        | "ThisFinancialYear" -> Ok DatePreset.ThisFinancialYear
        | "LastFinancialYear" -> Ok DatePreset.LastFinancialYear
        | "Custom" -> Ok DatePreset.Custom
        | other ->
            Error (
                ValidationFailed
                    $"\"{other}\" is not a valid date preset, expecting one \
                    of \"AnyTime\", \"ThisMonth\", \"LastMonth\", \
                    \"ThisYear\", \"LastYear\", \"ThisFinancialYear\", \
                    \"LastFinancialYear\", or \"Custom\"."
            )

    /// <summary>The first and last days of a preset other than custom, from
    /// the client's today. "Last" is the period before the one containing
    /// today.</summary>
    let resolve (today : DateOnly) (preset : DatePreset) =
        let days (frequency : Frequency) (isLast : bool) =
            let current = ReportingPeriod.containing frequency today

            let period =
                if isLast then ReportingPeriod.previous current else current

            Some (ReportingPeriod.fromDate period),
            Some (ReportingPeriod.toDate period)

        match preset with
        | DatePreset.AnyTime
        | DatePreset.Custom -> None, None
        | DatePreset.ThisMonth -> days Monthly false
        | DatePreset.LastMonth -> days Monthly true
        | DatePreset.ThisYear -> days CalendarYear false
        | DatePreset.LastYear -> days CalendarYear true
        | DatePreset.ThisFinancialYear -> days FinancialYear false
        | DatePreset.LastFinancialYear -> days FinancialYear true

    let private dates (today : DateOnly) (req : SearchDatesRequest) =
        result {
            let! preset = parsePreset req.Preset

            match preset, req.From, req.To with
            | DatePreset.Custom, Some from, Some ``to`` when from > ``to`` ->
                return!
                    Error (
                        ValidationFailed
                            "The first day must be on or before the last day"
                    )
            | DatePreset.Custom, from, ``to`` -> return from, ``to``
            | _, None, None -> return resolve today preset
            | _ ->
                return!
                    Error (
                        ValidationFailed
                            "Only custom dates take a first or last day"
                    )
        }

    /// <summary>Parse a criterion's state and id together: the states that
    /// take no id, and the one that needs an id.</summary>
    let private stateWithId
        (name : string)
        (states : (string * 'Criterion) list)
        (idState : string, withId : Guid -> 'Criterion)
        (state : string)
        (id : Guid option)
        =
        match List.tryFind (fst >> (=) state) states, id with
        | Some (_, criterion), None -> Ok criterion
        | Some _, Some _ ->
            Error (ValidationFailed $"The {name} state {state} takes no id")
        | None, Some id when state = idState -> Ok (withId id)
        | None, None when state = idState ->
            Error (ValidationFailed $"The {name} state {idState} needs an id")
        | None, _ ->
            let expected =
                List.map fst states @ [ idState ]
                |> List.map (sprintf "\"%s\"")
                |> String.concat ", "

            Error (
                ValidationFailed
                    $"\"{state}\" is not a valid {name} state, expecting one \
                    of {expected}."
            )

    let private account (req : SearchAccountRequest) =
        stateWithId
            "account"
            [
                "Any", AccountCriterion.Any
                "NoAccount", AccountCriterion.NoAccount
            ]
            ("Account", AccountCriterion.Account)
            req.State
            req.Id

    let private tag (req : SearchTagRequest) =
        stateWithId
            "tag"
            [
                "Any", TagCriterion.Any
                "WithoutTag", TagCriterion.WithoutTag
                "Untagged", TagCriterion.Untagged
                "Dismissed", TagCriterion.Dismissed
                "Transfer", TagCriterion.Transfer
            ]
            ("Tag", TagCriterion.Tag)
            req.State
            req.Id

    let private direction (value : string) =
        match value with
        | "Any" -> Ok Direction.Any
        | "Credit" -> Ok Direction.Credit
        | "Debit" -> Ok Direction.Debit
        | other ->
            Error (
                ValidationFailed
                    $"\"{other}\" is not a valid direction, expecting one of \
                    \"Any\", \"Credit\", or \"Debit\"."
            )

    /// <summary>A size is money: non-negative, with at most two decimal
    /// places.</summary>
    let private size (name : string) (value : decimal) =
        if value < 0m then
            Error (ValidationFailed $"The {name} cannot be negative")
        elif Money.roundToCents value <> value then
            Error (
                ValidationFailed
                    $"The {name} can have at most two decimal places"
            )
        else
            Ok (Money.create value)

    let private sizes (req : SearchAmountRequest) =
        result {
            let! minimum = req.Minimum |> Option.traverseResult (size "minimum")
            let! maximum = req.Maximum |> Option.traverseResult (size "maximum")

            match minimum, maximum with
            | Some minimum, Some maximum when
                Money.value minimum > Money.value maximum
                ->
                return!
                    Error (
                        ValidationFailed
                            "The minimum cannot be more than the maximum"
                    )
            | _ -> return minimum, maximum
        }

    /// <summary>Validate a request, reporting every failure in one error.
    /// Returns the search and where its page starts.</summary>
    let validate
        (req : SearchRequest)
        : Result<Search * Cursor option, DomainError> =
        validation {
            let! text = text req.Criteria.Text
            and! from, ``to`` = dates req.Today req.Criteria.Dates
            and! account = account req.Criteria.Account
            and! tag = tag req.Criteria.Tag
            and! direction = direction req.Criteria.Amount.Direction
            and! minimum, maximum = sizes req.Criteria.Amount
            and! cursor = req.Cursor |> Option.traverseResult Cursor.parse

            let search = {
                Text = text
                From = from
                To = ``to``
                Account = account
                Tag = tag
                Direction = direction
                Minimum = minimum
                Maximum = maximum
            }

            return search, cursor
        }
        |> DomainError.joinValidationErrors

    /// <summary>Split the matches read for a page, up to one more than the
    /// page size, into the page and the cursor for the next page, or none on
    /// the last page.</summary>
    let page (cursorOf : 'Match -> Cursor) (matches : 'Match list) =
        let page = List.truncate PageSize matches

        let cursor =
            if List.length matches > PageSize then
                List.tryLast page |> Option.map cursorOf
            else
                None

        page, cursor
