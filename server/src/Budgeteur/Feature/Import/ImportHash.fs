namespace Budgeteur.Feature.Import

/// <summary>The hash that recognises a statement row the user has already
/// imported, so a repeated or overlapping import skips it. See decision 6 in
/// docs/csv-import.md.</summary>
module ImportHash =
    open System
    open System.Security.Cryptography
    open System.Text

    open Budgeteur.Domain.Account

    /// <summary>Part of the hashed input, so a change to how the input is
    /// built can never match a hash from before it.</summary>
    [<Literal>]
    let private Version = "budgeteur-import-v1"

    /// <summary>SHA-256 over the version, the statement's account number, and
    /// the row's identity fields in canonical form, as lowercase hex. Each part
    /// is prefixed with its length, so no two lists of parts hash the same
    /// input. Changing this changes every stored hash: re-imports would
    /// duplicate every transaction.</summary>
    let compute (accountNumber : AccountNumber) (identity : string list) =
        Version :: AccountNumber.value accountNumber :: identity
        |> List.map (fun part -> $"{part.Length}:{part}")
        |> String.concat ""
        |> Encoding.UTF8.GetBytes
        |> SHA256.HashData
        |> Convert.ToHexStringLower
