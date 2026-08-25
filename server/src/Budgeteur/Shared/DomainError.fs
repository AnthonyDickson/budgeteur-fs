namespace Budgeteur.Shared.DomainError

type DomainError =
    | ValidationFailed of string
    | NotFound of string
    | Conflict of string
    | UserNotFound
    | DatabaseError of string * exn option
    | UnhandledException of string * exn option
