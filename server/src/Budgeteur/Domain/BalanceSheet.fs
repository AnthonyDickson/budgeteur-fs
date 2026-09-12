namespace Budgeteur.Domain.BalanceSheet

open System

open Budgeteur.Domain.BalanceSheetItem

/// <summary>The balance sheet items a user tracks, all valued as of a single date.</summary>
type BalanceSheet = {
    /// <summary>The date the balances are accurate as of.</summary>
    StatementDate : DateOnly

    /// <summary>Every asset and liability currently being tracked.</summary>
    Items : BalanceSheetItem list
}

[<RequireQualifiedAccess>]
module BalanceSheet =
    let private sumWhere predicate (sheet : BalanceSheet) =
        sheet.Items
        |> List.filter predicate
        |> List.sumBy (fun item -> Balance.value item.Balance)

    /// <summary>Total value of everything owned, both current and non-current.</summary>
    let totalAssets (sheet : BalanceSheet) =
        sumWhere (fun item -> item.Kind = ItemKind.Asset) sheet

    /// <summary>Total value of everything owed, both current and non-current.</summary>
    let totalLiabilities (sheet : BalanceSheet) =
        sumWhere (fun item -> item.Kind = ItemKind.Liability) sheet

    /// <summary>Total assets minus total liabilities.</summary>
    let netWorth (sheet : BalanceSheet) =
        totalAssets sheet - totalLiabilities sheet

    /// <summary>Total value of assets expected to be realised within the current period.</summary>
    let totalCurrentAssets (sheet : BalanceSheet) =
        sumWhere (fun item -> item.Kind = ItemKind.Asset && item.Term = Term.Current) sheet

    /// <summary>Total value of liabilities expected to be settled within the current period.</summary>
    let totalCurrentLiabilities (sheet : BalanceSheet) =
        sumWhere (fun item -> item.Kind = ItemKind.Liability && item.Term = Term.Current) sheet

    /// <summary>
    /// Current assets minus current liabilities: the near-term position. Unlike net worth it
    /// excludes non-current debt, so it stays sensitive to near-term decisions.
    /// </summary>
    let workingCapital (sheet : BalanceSheet) =
        totalCurrentAssets sheet - totalCurrentLiabilities sheet
