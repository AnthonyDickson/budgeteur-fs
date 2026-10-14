namespace Budgeteur.Domain.BalanceSheet

open System

open Budgeteur.Domain.Account
open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Domain.Money
open Budgeteur.Domain.Side
open Budgeteur.Domain.Term

/// <summary>The items and accounts a user tracks: the two sources of lines.
/// The sheet stores no date of its own: it is drawn for the date the client
/// asks about, and each line carries its own as-of date. See decisions 4 and 5
/// in docs/balance-sheet.md.</summary>
type BalanceSheet = {
    /// <summary>Every asset and liability that is not an account, with its
    /// current value.</summary>
    Items : ItemValue list

    /// <summary>Every account, whether its balance is known or not.</summary>
    Accounts : AccountBalance list
}

/// <summary>Every item and account a user has, open or closed, each with its
/// observation history in any order: what a balance sheet for any statement
/// date is drawn from. See decision 3 in docs/reports.md.</summary>
type BalanceSheetHistory = {
    ItemHistories : (BalanceSheetItem * ItemObservation list) list
    AccountHistories : (Account * BalanceObservation list) list
}

/// <summary>Where a line sits on the sheet and the magnitude it adds there.
/// Both sources of lines reduce to this for the totals.</summary>
type private Line = {
    Side : Side
    Term : Term
    Amount : decimal
}

[<RequireQualifiedAccess>]
module BalanceSheet =
    /// <summary>The side and magnitude of an account's balance: an asset when
    /// it is zero or more, a liability when it is negative. An overdrawn
    /// chequing account is a current liability.</summary>
    let accountSide (balance : Money) : Side * decimal =
        let balance = Money.value balance

        if balance < 0m then
            Side.Liability, -balance
        else
            Side.Asset, balance

    /// <summary>The accounts whose balance is unknown. They are left out of
    /// the totals, since an unknown balance is not zero.</summary>
    let unknownBalances (sheet : BalanceSheet) : Account list =
        sheet.Accounts
        |> List.filter (fun account -> Option.isNone account.Current)
        |> List.map _.Account

    let private lines (sheet : BalanceSheet) : Line list =
        let items =
            sheet.Items
            |> List.map (fun item -> {
                Side = item.Item.Side
                Term = item.Item.Term
                Amount = Value.value item.Current.Value
            })

        let accounts =
            sheet.Accounts
            |> List.choose (fun account ->
                account.Current
                |> Option.map (fun current ->
                    let side, amount = accountSide current.Balance

                    {
                        Side = side
                        Term = account.Account.Term
                        Amount = amount
                    }))

        items @ accounts

    let private sumWhere predicate (sheet : BalanceSheet) =
        lines sheet |> List.filter predicate |> List.sumBy _.Amount

    /// <summary>Total value of everything owned, both current and
    /// non-current.</summary>
    let totalAssets (sheet : BalanceSheet) =
        sumWhere (fun line -> line.Side = Side.Asset) sheet

    /// <summary>Total value of everything owed, both current and
    /// non-current.</summary>
    let totalLiabilities (sheet : BalanceSheet) =
        sumWhere (fun line -> line.Side = Side.Liability) sheet

    /// <summary>Total value of assets expected to be realised within the
    /// current period.</summary>
    let totalCurrentAssets (sheet : BalanceSheet) =
        sumWhere
            (fun line -> line.Side = Side.Asset && line.Term = Term.Current)
            sheet

    /// <summary>Total value of liabilities expected to be settled within the
    /// current period.</summary>
    let totalCurrentLiabilities (sheet : BalanceSheet) =
        sumWhere
            (fun line -> line.Side = Side.Liability && line.Term = Term.Current)
            sheet

    /// <summary>Total value of assets **not** expected to be realised within
    /// the current period.</summary>
    let totalNonCurrentAssets (sheet : BalanceSheet) =
        sumWhere
            (fun line -> line.Side = Side.Asset && line.Term = Term.NonCurrent)
            sheet

    /// <summary>Total value of liabilities **not** expected to be settled
    /// within the current period.</summary>
    let totalNonCurrentLiabilities (sheet : BalanceSheet) =
        sumWhere
            (fun line ->
                line.Side = Side.Liability && line.Term = Term.NonCurrent)
            sheet

    /// <summary>Total assets minus total liabilities.</summary>
    let netWorth (sheet : BalanceSheet) =
        totalAssets sheet - totalLiabilities sheet

    /// <summary>
    /// Current assets minus current liabilities: the near-term position. Unlike
    /// net worth it excludes non-current debt, so it stays sensitive to
    /// near-term decisions.
    /// </summary>
    let workingCapital (sheet : BalanceSheet) =
        totalCurrentAssets sheet - totalCurrentLiabilities sheet

    /// <summary>Whether a line closed on <c>closedOn</c>, if ever, is still
    /// held on the date.</summary>
    let private isOpenOn (date : DateOnly) (closedOn : DateOnly option) =
        match closedOn with
        | Some closedOn -> date < closedOn
        | None -> true

    /// <summary>The observation with the latest as-of date on or before the
    /// date, if any.</summary>
    let private latestOnOrBefore
        (date : DateOnly)
        (asOf : 'Observation -> DateOnly)
        (observations : 'Observation list)
        =
        observations
        |> List.filter (fun observation -> asOf observation <= date)
        |> List.sortByDescending asOf
        |> List.tryHead

    /// <summary>
    /// The balance sheet drawn for a statement date. Each line's balance is
    /// its latest observation on or before the date. A line enters the sheet
    /// at its first observation and leaves it on its close date. An account
    /// with no observations at all has an unknown balance, as on the current
    /// sheet. See decision 3 in docs/reports.md.
    /// </summary>
    /// <remarks>
    /// Balances between observations are not interpolated: a line keeps its
    /// latest value until the next, and its as-of date shows how old it is.
    /// </remarks>
    let asOf
        (statementDate : DateOnly)
        (history : BalanceSheetHistory)
        : BalanceSheet =
        let items =
            history.ItemHistories
            |> List.filter (fun (item, _) ->
                isOpenOn statementDate item.ClosedOn)
            |> List.choose (fun (item, observations) ->
                latestOnOrBefore
                    statementDate
                    (fun (observation : ItemObservation) -> observation.AsOf)
                    observations
                |> Option.map (fun current -> {
                    Item = item
                    Current = current
                }))

        let accounts =
            history.AccountHistories
            |> List.filter (fun (account, _) ->
                isOpenOn statementDate account.ClosedOn)
            |> List.choose (fun (account, observations) ->
                match
                    observations,
                    latestOnOrBefore
                        statementDate
                        (fun (observation : BalanceObservation) ->
                            observation.AsOf)
                        observations
                with
                | [], _ -> Some { Account = account; Current = None }
                | _, Some current ->
                    Some {
                        Account = account
                        Current = Some current
                    }
                | _, None -> None)

        { Items = items; Accounts = accounts }
