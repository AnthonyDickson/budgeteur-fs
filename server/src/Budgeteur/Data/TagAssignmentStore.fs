namespace Budgeteur.Data

/// <summary>Writes tag assignments. Every slice that tags transactions writes
/// through here, so an assignment is written one way.</summary>
module TagAssignmentStore =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query
    open SqlHydra.Query.SqliteExtensions

    open Budgeteur.Data.Db
    open Budgeteur.Domain.TagAssignment

    /// <summary>Set a transaction's assignment: insert or replace it, or delete
    /// it when the transaction is untagged. The caller checks that the
    /// transaction and tag belong to the user.</summary>
    let save
        (queryContext : QueryContext)
        (userId : string)
        (transactionId : Guid)
        (assignment : TagAssignment option)
        : Task<unit> =
        task {
            match assignment with
            | Some assignment ->
                let row =
                    TagAssignmentCodec.toRow transactionId userId assignment

                let! _ =
                    insertTask queryContext {
                        for a in main.TagAssignments do
                            entity row

                            onConflictDoUpdate
                                a.TransactionId
                                (a.TagId, a.Source)
                    }

                ()
            | None ->
                let! _ =
                    deleteTask queryContext {
                        for a in main.TagAssignments do
                            where (
                                a.TransactionId = transactionId
                                && a.UserId = userId
                            )
                    }

                ()
        }
