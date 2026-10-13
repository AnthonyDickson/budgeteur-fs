namespace Budgeteur.Data

/// <summary>Writes categorisations. Every slice that tags transactions writes
/// through here, so a categorisation is written one way.</summary>
module CategorisationStore =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query
    open SqlHydra.Query.SqliteExtensions

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation

    /// <summary>Set a transaction's categorisation: insert or replace it, or
    /// delete it when the transaction is untagged. The caller checks that the
    /// transaction and tag belong to the user.</summary>
    let save
        (queryContext : QueryContext)
        (userId : string)
        (transactionId : Guid)
        (categorisation : Categorisation option)
        : Task<unit> =
        task {
            match categorisation with
            | Some categorisation ->
                let row =
                    CategorisationCodec.toRow
                        transactionId
                        userId
                        categorisation

                let! _ =
                    insertTask queryContext {
                        for a in main.Categorisations do
                            entity row

                            onConflictDoUpdate
                                a.TransactionId
                                (a.TagId, a.Source)
                    }

                ()
            | None ->
                let! _ =
                    deleteTask queryContext {
                        for a in main.Categorisations do
                            where (
                                a.TransactionId = transactionId
                                && a.UserId = userId
                            )
                    }

                ()
        }
