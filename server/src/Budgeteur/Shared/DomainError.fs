namespace Budgeteur.Shared.DomainError

type DomainError =
    /// The client provided input that violates domain rules.
    /// This may include database constraint violations.
    | ValidationFailed of string
    /// The requested resource could not be found.
    | NotFound of string
    /// The "sub" claim could not be found in the OIDC token.
    | Unauthorised
    /// An unhandled database constraint violation. Constraint violations should
    /// be handled via helpers that explicitly check the constraint and return a
    /// `ValidationFailed` error. This error variant exists to make it clear
    /// where there are unhandled constraints.
    | Conflict of exn
    /// An unhandled database error.
    | DatabaseError of exn
    | UnhandledException of exn

module DomainError =
    open System

    /// <summary>Combine the failures of an applicative validation into one
    /// <c>ValidationFailed</c> error, so a client sees every failure in one
    /// response. Validation only produces <c>ValidationFailed</c>.</summary>
    let joinValidationErrors
        (validationResult : Result<'Ok, DomainError list>)
        : Result<'Ok, DomainError> =
        match validationResult with
        | Ok value -> Ok value
        | Error errors ->
            errors
            |> List.map (fun error ->
                match error with
                | ValidationFailed error -> error
                // TODO: Is there a way to remove this exception? Maybe have the
                // validation functions return a scalar value (e.g. just a
                // string)? It would be nice if this could have nice error
                // messages like Thoth.
                | other -> failwithf $"unexpected domain error: {other}")
            |> fun errorStrings ->
                "Validation failed:\n\t" + String.Join ("\n\t", errorStrings)
            |> ValidationFailed
            |> Error
