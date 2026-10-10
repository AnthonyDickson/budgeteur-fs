namespace Budgeteur.Data

module TagAssignmentCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.TagAssignment

    let toRow
        (transactionId : Guid)
        (userId : string)
        (assignment : TagAssignment)
        : main.TagAssignments = {
        TransactionId = transactionId
        UserId = userId
        TagId = assignment.TagId
        Source = TagSource.toString assignment.Source
    }

    let fromRow (row : main.TagAssignments) : TagAssignment = {
        TagId = row.TagId
        Source =
            match TagSource.parse row.Source with
            | Ok source -> source
            // The database checks this column, so in practice this arm is
            // unreachable
            | Error error -> failwith error
    }
