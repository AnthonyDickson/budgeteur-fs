namespace Budgeteur.Domain.Term

/// <summary>
/// Whether a balance sheet line is expected to be realised (assets) or settled
/// (liabilities) within the current accounting period, conventionally within
/// about 12 months. Items and accounts both have one. See decision 7 in
/// docs/balance-sheet.md.
/// </summary>
type Term =
    | Current
    | NonCurrent

module Term =
    let toString term =
        match term with
        | Current -> "Current"
        | NonCurrent -> "NonCurrent"

    let parse string =
        match string with
        | "Current" -> Ok Current
        | "NonCurrent" -> Ok NonCurrent
        | other ->
            Error
                $"\"{other}\" is not a valid value for Term, expecting one \
                of \"Current\" or \"NonCurrent\"."
