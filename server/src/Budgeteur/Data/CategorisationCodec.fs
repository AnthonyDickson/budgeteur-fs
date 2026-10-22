namespace Budgeteur.Data

module CategorisationCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation

    [<Literal>]
    let TaggedKind = "Tagged"

    [<Literal>]
    let DismissedKind = "Dismissed"

    /// <summary>The kind of a transfer's row. Queries that leave transfers out
    /// compare against it.</summary>
    [<Literal>]
    let TransferKind = "Transfer"

    /// <summary>Only a tagged row has a tag; every row has a source, which is
    /// manual for a dismissal. The schema checks both.</summary>
    let toRow
        (transactionId : Guid)
        (userId : string)
        (categorisation : Categorisation)
        : main.Categorisations =
        let kind, tagId =
            match categorisation with
            | Categorisation.Tagged (tagId, _) -> TaggedKind, Some tagId
            | Categorisation.Dismissed -> DismissedKind, None
            | Categorisation.Transfer _ -> TransferKind, None

        {
            TransactionId = transactionId
            UserId = userId
            Kind = kind
            TagId = tagId
            Source = Source.toString (Categorisation.source categorisation)
        }

    let fromRow (row : main.Categorisations) : Categorisation =
        // The database checks these columns, so in practice the failing arms
        // are unreachable.
        let source () =
            match Source.parse row.Source with
            | Ok source -> source
            | Error error -> failwith error

        match row.Kind, row.TagId with
        | TaggedKind, Some tagId -> Categorisation.Tagged (tagId, source ())
        | DismissedKind, _ -> Categorisation.Dismissed
        | TransferKind, _ -> Categorisation.Transfer (source ())
        | kind, _ -> failwith $"Invalid categorisation kind \"{kind}\""
