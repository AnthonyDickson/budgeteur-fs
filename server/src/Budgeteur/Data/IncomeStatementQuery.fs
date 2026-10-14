namespace Budgeteur.Data

/// <summary>The reads an income statement is computed from, shared by the
/// slices that compute one.</summary>
module IncomeStatementQuery =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.IncomeStatement

    /// <summary>Load the user's non-transfer transactions in the period, each
    /// with its tag.</summary>
    let entries
        (queryContext : QueryContextFactory)
        (userId : string)
        (period : Period)
        : Task<Entry list> =
        task {
            let fromDate = Period.fromDate period
            let toDate = Period.toDate period
            let transfer = Some CategorisationCodec.TransferKind

            let! transactions =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        where (
                            t.UserId = userId
                            && t.Date >= fromDate
                            && t.Date <= toDate
                            && (isNullValue a.Kind || a.Kind <> transfer)
                        )

                        select (t.Amount, a.TagId)
                }

            and! tags =
                selectTask queryContext {
                    for t in main.Tags do
                        where (t.UserId = userId)
                }

            let tagsById =
                tags
                |> Seq.map (fun row ->
                    let tag = TagCodec.fromRow row
                    tag.Id, tag)
                |> Map.ofSeq

            return
                transactions
                |> Seq.map (fun (amount, tagId) -> {
                    Entry.Amount = amount
                    Tag =
                        tagId
                        |> Option.bind (fun id -> Map.tryFind id tagsById)
                })
                |> List.ofSeq
        }

    /// <summary>The date of the user's earliest transaction, if any.</summary>
    let firstTransactionDate
        (queryContext : QueryContextFactory)
        (userId : string)
        : Task<DateOnly option> =
        selectTask queryContext {
            for t in main.Transactions do
                where (t.UserId = userId)
                orderBy t.Date
                select t.Date
                tryHead
        }
