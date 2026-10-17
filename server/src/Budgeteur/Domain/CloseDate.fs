namespace Budgeteur.Domain.CloseDate

open System

open Budgeteur.Domain.AsOfDate
open Budgeteur.Shared.DomainError

/// <summary>The calendar date a line was closed: an item sold or repaid, or
/// an account closed. See decision 4 in docs/reports.md.</summary>
[<RequireQualifiedAccess>]
module CloseDate =
    /// <summary>Reject a close date later than the latest as-of date at the
    /// instant <c>now</c>, as for balances, so a line cannot be closed in
    /// advance. The current balance sheet can then leave out every closed
    /// line without knowing the client's today.</summary>
    let validate
        (now : DateTimeOffset)
        (closedOn : DateOnly)
        : Result<DateOnly, DomainError> =
        let latest = AsOfDate.latest now

        if closedOn > latest then
            Error (
                ValidationFailed
                    $"The close date {closedOn:O} is in the future. \
                    The latest accepted date is {latest:O}."
            )
        else
            Ok closedOn
