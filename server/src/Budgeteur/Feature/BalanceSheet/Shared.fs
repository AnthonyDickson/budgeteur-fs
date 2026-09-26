namespace Budgeteur.Feature.BalanceSheet

open System
open System.ComponentModel.DataAnnotations

open Budgeteur.Domain.BalanceSheetItem
open Budgeteur.Shared.OpenApi

/// <summary>Reads the current instant. The item write endpoints take one so a caller can control the
/// <c>StatementDate</c> a write stamps, which is otherwise only ever "now".</summary>
type Clock = unit -> DateTimeOffset

module Clock =
    /// <summary>The real clock: the current instant, in UTC.</summary>
    let system : Clock = fun () -> DateTimeOffset.UtcNow

module BalanceSheetStore =
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data.Db

    /// <summary> Update the statement date on the user's balance sheet if it exists, otherwise create it.
    /// The instant is stored in UTC, as the <c>DATETIME</c> column convention requires.</summary>
    let updateOrCreate (queryContext : QueryContext) (now : DateTimeOffset) (userId : string) : Task<unit> =
        task {
            // The column carries no offset, so it has to be written as UTC. Converting here means
            // the stored instant is right whatever offset the clock reports.
            let statementDate = now.UtcDateTime

            let! sheetCount =
                selectTask queryContext {
                    for b in main.BalanceSheets do
                        where (b.UserId = userId)
                        count
                }

            let exists = sheetCount > 0

            if exists then
                let! _ =
                    updateTask queryContext {
                        for b in main.BalanceSheets do
                            set b.StatementDate statementDate
                            where (b.UserId = userId)
                    }

                return ()
            else
                let! _ =
                    insertTask queryContext {
                        for b in main.BalanceSheets do
                            entity {
                                UserId = userId
                                StatementDate = statementDate
                            }
                    }

                return ()
        }

/// <summary>Payload for creating or updating a balance sheet item.</summary>
type WriteBalanceSheetItemRequest = {
    /// <summary>A human-readable name, e.g. "Chequing account" or "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability.</summary>
    [<SchemaHint.Enum(typeof<ItemKind>)>]
    Kind : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's value. Direction is implied by Kind.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Balance : decimal
}

module WriteBalanceSheetItemRequest =
    open FsToolkit.ErrorHandling

    open Budgeteur.Shared.DomainError

    let private joinValidationErrors (validationResult : Validation<'Ok, DomainError>) : Result<'Ok, DomainError> =
        match validationResult with
        | Ok value -> Ok value
        | Error errors ->
            errors
            |> List.map (fun error ->
                match error with
                | ValidationFailed error -> error
                // TODO: Is there a way to remove this exception?
                // Maybe have the validation functions return a scalar value (e.g. just a string)?
                // It would be nice if this could have nice error messages like Thoth.
                | other -> failwithf $"unexpected domain error: {other}")
            |> fun errorStrings -> "Validation failed:\n\t" + String.Join ("\n\t", errorStrings)
            |> ValidationFailed
            |> Error

    let validate (req : WriteBalanceSheetItemRequest) (id : Guid) =
        validation {
            let! name = ItemName.create req.Name
            and! balance = Balance.create req.Balance
            and! kind = ItemKind.parse req.Kind |> Result.mapError ValidationFailed
            and! term = Term.parse req.Term |> Result.mapError ValidationFailed

            let item : BalanceSheetItem = {
                Id = id
                Name = name
                Kind = kind
                Term = term
                Balance = balance
            }

            return item
        }
        |> joinValidationErrors

/// <summary>A single line on the balance sheet: one asset or one liability.</summary>
type BalanceSheetItemResponse = {
    /// <summary>Unique identifier for the item.</summary>
    Id : Guid

    /// <summary>A human-readable name, e.g. "Chequing account" or "Mortgage".</summary>
    [<MinLength(1)>]
    [<MaxLength(ItemName.MaxLength)>]
    Name : string

    /// <summary>Whether the item is an asset or a liability.</summary>
    [<SchemaHint.Enum(typeof<ItemKind>)>]
    Kind : string

    /// <summary>Whether the item is current or non-current.</summary>
    [<SchemaHint.Enum(typeof<Term>)>]
    Term : string

    /// <summary>The positive magnitude of the item's value. Direction is implied by Kind.</summary>
    [<SchemaHint.Decimal(NonNegative = true)>]
    Balance : decimal
}

module BalanceSheetItemResponse =
    let fromDomain (item : BalanceSheetItem) : BalanceSheetItemResponse = {
        Id = item.Id
        Name = ItemName.value item.Name
        Kind = ItemKind.toString item.Kind
        Term = Term.toString item.Term
        Balance = Balance.value item.Balance
    }
