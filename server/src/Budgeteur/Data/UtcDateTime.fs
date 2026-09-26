namespace Budgeteur.Data

open System

/// <summary>Conversions for the <c>DATETIME</c> column convention: the columns carry no offset and
/// values are assumed to be UTC. See "Date and datetime columns" in docs/database.md. The names
/// mirror the codecs' <c>fromRow</c>/<c>toRow</c>: same direction, one layer out.</summary>
[<RequireQualifiedAccess>]
module UtcDateTime =
    /// <summary>Restore the UTC kind of a value read from a column, which the provider hands back as
    /// <c>Unspecified</c>. Skipping this leaves the value reinterpreted as local time on the way
    /// out.</summary>
    let fromColumn (value : DateTime) =
        DateTime.SpecifyKind (value, DateTimeKind.Utc)

    /// <summary>The value to store in a column for the given instant. Takes a
    /// <c>DateTimeOffset</c> because given a <c>DateTime</c> there is nothing to convert: an
    /// <c>Unspecified</c> value would have to be assumed local, which is the shift this convention
    /// exists to prevent.</summary>
    let toColumn (value : DateTimeOffset) = value.UtcDateTime
