namespace Budgeteur.Feature.QuickTag

/// <summary>The write the quick tag operations share: set one queued
/// transaction's categorisation, replacing whatever it had.</summary>
module QuickTagWrite =
    open System

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Shared.DomainError

    /// <summary>Set the user's transaction's categorisation, reading the
    /// transaction in the same database transaction as the write. Fails with
    /// <c>NotFound</c> when the user has no transaction with the id. The caller
    /// checks that a tag belongs to the user.</summary>
    let save
        (queryContext : QueryContextFactory)
        (userId : string)
        (transactionId : Guid)
        (categorisation : Categorisation option)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! found =
                selectTask ctx {
                    for t in main.Transactions do
                        where (t.Id = transactionId && t.UserId = userId)
                        count
                }

            match found with
            | 0 ->
                return
                    Error (NotFound $"Transaction %O{transactionId} not found")
            | _ ->
                do!
                    CategorisationStore.save
                        ctx
                        userId
                        transactionId
                        categorisation

                ctx.CommitTransaction ()
                return Ok ()
        }
