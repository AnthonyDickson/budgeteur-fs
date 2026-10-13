namespace Budgeteur.Shared.Clock

open System

/// <summary>Reads the current instant. Endpoints that depend on "now" take one
/// so a caller can control it.</summary>
type Clock = unit -> DateTimeOffset

module Clock =
    /// <summary>The real clock: the current instant, in UTC.</summary>
    let system : Clock = fun () -> DateTimeOffset.UtcNow
