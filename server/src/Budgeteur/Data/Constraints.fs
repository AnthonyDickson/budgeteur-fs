namespace Budgeteur.Data

/// <summary>A failed constraint check. Constraint checks mirror the database's integrity
/// constraints but produce a friendly, actionable error message. This type is deliberately
/// narrower than <c>DomainError</c>: it can only represent validation failures, so combining
/// multiple failures can never drop or misclassify an error. Constraint errors are mapped to
/// <c>DomainError.ValidationFailed</c> by <c>requireAll</c> and <c>requireOne</c>.</summary>
type ConstraintError = ConstraintError of string

/// <summary>Explicit checks for the database's integrity constraints. These checks exist to
/// provide meaningful error messages, since SQLite does not always report which column
/// triggered a constraint violation. Always run checks through <c>requireAll</c> (or
/// <c>requireOne</c> for a single check) so failures are mapped to a <c>DomainError</c>.</summary>
module Constraints =
    open System
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Shared.DomainError

    /// <summary>Combine a list of failed checks into a single error, joining their messages. The
    /// input is guaranteed to be non-empty: it comes from a failed
    /// <c>List.sequenceTaskResultA</c>, which fails with at least one error.</summary>
    let private combineValidationErrors =
        function
        | [] -> invalidOp "combineValidationErrors requires at least one error"
        | errors ->
            errors
            |> List.map (fun (ConstraintError error) -> error)
            |> String.concat "; "
            |> ConstraintError

    /// <summary>Run all constraint checks, collecting every failure instead of stopping at the
    /// first. Checks run concurrently (applicative) and their messages are joined into a single
    /// <c>ValidationFailed</c> error, so a client sees all violations in one response.</summary>
    let requireAll (constraints : Task<Result<unit, ConstraintError>> list) : Task<Result<unit, DomainError>> =
        task {
            match! List.sequenceTaskResultA constraints with
            | Ok _ -> return Ok ()
            | Error errors ->
                let (ConstraintError error) = combineValidationErrors errors
                return Error (ValidationFailed error)
        }

    /// <summary>Run a single constraint check, mapping any failure to a <c>ValidationFailed</c> error.</summary>
    let requireOne (constraint_ : Task<Result<unit, ConstraintError>>) : Task<Result<unit, DomainError>> =
        requireAll [ constraint_ ]

    /// <summary>Verify that a tag with the given ID exists and belongs to the user.</summary>
    let requireTagExists
        (queryContext : QueryContextFactory)
        (userId : string)
        (tagId : Guid)
        : Task<Result<unit, ConstraintError>> =
        task {
            let! rowCount =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.Id = tagId && t.UserId = userId)
                        count
                }

            return
                if rowCount > 0 then
                    Ok ()
                else
                    Error (ConstraintError $"Could not find a tag with the ID {tagId}")
        }

    // Omit type annotations so that this function inherits signature changes from the wrapped function.
    /// <summary>Verify that the referenced tag exists and belongs to the user. Skips the check
    /// when no tag is referenced (<c>None</c> succeeds).</summary>
    let requireTagIfReferenced queryContext userId tagId =
        match tagId with
        | Some tagId -> requireTagExists queryContext userId tagId
        | None -> Task.FromResult (Ok ())
