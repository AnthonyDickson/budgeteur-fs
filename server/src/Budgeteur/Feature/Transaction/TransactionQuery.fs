namespace Budgeteur.Feature.Transaction

/// <summary>The slice's read shape: a transaction with its tag, if any, and its
/// account's name, if any. Writes respond with it too, so every response
/// carries the same fields.</summary>
module TransactionQuery =
    open System

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Feature.Transaction

    let private fromJoinedRow
        (
            row : main.Transactions,
            assignment : main.LeftJoined.TagAssignments,
            accountName : string option
        ) =
        TransactionCodec.fromRow row,
        assignment.ToOption () |> Option.map TagAssignmentCodec.fromRow,
        accountName

    /// <summary>Every transaction of the user.</summary>
    let readAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.TagAssignments
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.UserId = userId)
                        select (t, a, account.Name)
                }

            return rows |> Seq.map fromJoinedRow |> List.ofSeq
        }

    /// <summary>The user's transaction with the id, if any.</summary>
    let tryRead
        (queryContext : QueryContextFactory)
        (userId : string)
        (id : Guid)
        =
        task {
            let! row =
                selectTask queryContext {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.TagAssignments
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.Id = id && t.UserId = userId)
                        select (t, a, account.Name)
                        tryHead
                }

            return Option.map fromJoinedRow row
        }
