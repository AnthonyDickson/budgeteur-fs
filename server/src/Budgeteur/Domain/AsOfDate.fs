namespace Budgeteur.Domain.AsOfDate

open System

open Budgeteur.Shared.DomainError

/// <summary>The calendar date a balance is accurate as of. Every balance the
/// user enters carries one. See decision 4 in docs/balance-sheet.md.</summary>
[<RequireQualifiedAccess>]
module AsOfDate =
    /// <summary>The latest as-of date accepted at the instant <c>now</c>: the
    /// server's UTC date plus one day. The extra day covers a client whose
    /// local date is ahead of UTC.</summary>
    let latest (now : DateTimeOffset) =
        (DateOnly.FromDateTime now.UtcDateTime).AddDays 1

    /// <summary>Reject an as-of date later than <c>latest</c>, so a mistyped
    /// future date cannot stay current.</summary>
    let validate
        (now : DateTimeOffset)
        (asOf : DateOnly)
        : Result<DateOnly, DomainError> =
        let latest = latest now

        if asOf > latest then
            Error (
                ValidationFailed
                    $"""The as-of date {asOf.ToString "O"} is in the future. \
                    The latest accepted date is {latest.ToString "O"}."""
            )
        else
            Ok asOf
