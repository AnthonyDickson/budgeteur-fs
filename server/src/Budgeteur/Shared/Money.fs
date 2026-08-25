namespace Budgeteur.Shared.Money

open System

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
