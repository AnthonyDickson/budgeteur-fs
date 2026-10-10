namespace Budgeteur.Shared.Money

open System

/// <summary>A signed monetary amount in whole cents. The only way to build one from untrusted input is
/// <c>Money.create</c>, which rounds, so an amount with fractions of a cent cannot be stored.</summary>
type Money = private Money of decimal

/// <summary>Helpers for monetary values.</summary>
[<RequireQualifiedAccess>]
module Money =
    /// <summary>
    /// Round a monetary value to the nearest cent (2 decimal places), away from zero.
    /// </summary>
    /// <remarks>
    /// Named distinctly from F# core <c>round</c> (which rounds to the nearest
    /// integer) so a missing call fails loudly in review instead of silently
    /// falling back to the wrong rounding, as the Update endpoint once did.
    /// </remarks>
    let roundToCents (amount : decimal) =
        Decimal.Round (amount, decimals = 2, mode = MidpointRounding.AwayFromZero)

    /// <summary>Round an amount to cents.</summary>
    let create (amount : decimal) = Money (roundToCents amount)

    let value (Money amount) = amount

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromDecimal amount = Money amount
