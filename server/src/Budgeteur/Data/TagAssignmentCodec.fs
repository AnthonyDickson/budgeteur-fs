namespace Budgeteur.Data

module TagAssignmentCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.TagAssignment

    /// <summary>A dismissal is a row without a tag, with the <c>Manual</c>
    /// source the schema requires of one.</summary>
    let toRow
        (transactionId : Guid)
        (userId : string)
        (assignment : TagAssignment)
        : main.TagAssignments =
        let tagId, source =
            match assignment with
            | TagAssignment.Tagged (tagId, source) -> Some tagId, source
            | TagAssignment.Dismissed -> None, TagSource.Manual

        {
            TransactionId = transactionId
            UserId = userId
            TagId = tagId
            Source = TagSource.toString source
        }

    let fromRow (row : main.TagAssignments) : TagAssignment =
        match row.TagId with
        | Some tagId ->
            let source =
                match TagSource.parse row.Source with
                | Ok source -> source
                // The database checks this column, so in practice this arm is
                // unreachable
                | Error error -> failwith error

            TagAssignment.Tagged (tagId, source)
        | None -> TagAssignment.Dismissed
