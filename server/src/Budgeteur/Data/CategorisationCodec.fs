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

    /// <summary>Only a tagged row has a tag and a source; the schema checks
    /// both.</summary>
    let toRow
        (transactionId : Guid)
        (userId : string)
        (categorisation : Categorisation)
        : main.Categorisations =
        let kind, tagId, source =
            match categorisation with
            | Categorisation.Tagged (tagId, source) ->
                TaggedKind, Some tagId, Some (TagSource.toString source)
            | Categorisation.Dismissed -> DismissedKind, None, None
            | Categorisation.Transfer -> TransferKind, None, None

        {
            TransactionId = transactionId
            UserId = userId
            Kind = kind
            TagId = tagId
            Source = source
        }

    let fromRow (row : main.Categorisations) : Categorisation =
        // The database checks these columns, so in practice the failing arms
        // are unreachable.
        match row.Kind, row.TagId, row.Source with
        | TaggedKind, Some tagId, Some source ->
            match TagSource.parse source with
            | Ok source -> Categorisation.Tagged (tagId, source)
            | Error error -> failwith error
        | DismissedKind, _, _ -> Categorisation.Dismissed
        | TransferKind, _, _ -> Categorisation.Transfer
        | kind, _, _ -> failwith $"Invalid categorisation kind \"{kind}\""
