namespace Budgeteur.Data

module CategorisationCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation

    /// <summary>A dismissal is a row without a tag, with the <c>Manual</c>
    /// source the schema requires of one.</summary>
    let toRow
        (transactionId : Guid)
        (userId : string)
        (categorisation : Categorisation)
        : main.Categorisations =
        let tagId, source =
            match categorisation with
            | Categorisation.Tagged (tagId, source) -> Some tagId, source
            | Categorisation.Dismissed -> None, TagSource.Manual

        {
            TransactionId = transactionId
            UserId = userId
            TagId = tagId
            Source = TagSource.toString source
        }

    let fromRow (row : main.Categorisations) : Categorisation =
        match row.TagId with
        | Some tagId ->
            let source =
                match TagSource.parse row.Source with
                | Ok source -> source
                // The database checks this column, so in practice this arm is
                // unreachable
                | Error error -> failwith error

            Categorisation.Tagged (tagId, source)
        | None -> Categorisation.Dismissed
