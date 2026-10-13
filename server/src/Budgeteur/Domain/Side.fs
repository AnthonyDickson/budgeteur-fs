namespace Budgeteur.Domain.Side

/// <summary>Which side of the balance sheet a line is on: something owned (an
/// asset) or owed (a liability). Fixed for an item; for an account it follows
/// the sign of the balance. See decisions 3 and 5 in
/// docs/balance-sheet.md.</summary>
type Side =
    | Asset
    | Liability

module Side =
    let toString side =
        match side with
        | Asset -> "Asset"
        | Liability -> "Liability"

    let parse string =
        match string with
        | "Asset" -> Ok Asset
        | "Liability" -> Ok Liability
        | other ->
            Error
                $"\"{other}\" is not a valid value for Side, expecting one of \
                \"Asset\" or \"Liability\"."
