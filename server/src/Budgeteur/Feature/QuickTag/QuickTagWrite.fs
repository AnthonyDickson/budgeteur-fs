namespace Budgeteur.Feature.QuickTag

/// <summary>The write both quick tag operations share: set one queued
/// transaction's categorisation.</summary>
module QuickTagWrite =
    open System

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Shared.DomainError

    /// <summary>Set the user's transaction's categorisation, reading the
    /// transaction in the same database transaction as the write. Fails with
    /// <c>NotFound</c> when the user has no transaction with the id, and with
    /// <c>ValidationFailed</c> for a transfer, which has no categorisation. The
    /// caller checks that a tag belongs to the user.</summary>
    let save
        (queryContext : QueryContextFactory)
        (userId : string)
        (transactionId : Guid)
        (categorisation : Categorisation option)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! isTransfer =
                selectTask ctx {
                    for t in main.Transactions do
                        where (t.Id = transactionId && t.UserId = userId)
                        select t.IsTransfer
                        tryHead
                }

            match isTransfer with
            | None ->
                return
                    Error (NotFound $"Transaction %O{transactionId} not found")
            | Some true ->
                return
                    Error (
                        ValidationFailed
                            "A transfer has no tag, so it cannot be tagged or \
                            dismissed"
                    )
            | Some false ->
                do!
                    CategorisationStore.save
                        ctx
                        userId
                        transactionId
                        categorisation

                ctx.CommitTransaction ()
                return Ok ()
        }
