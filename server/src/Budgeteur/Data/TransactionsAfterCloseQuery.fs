namespace Budgeteur.Data

/// <summary>Finds transactions dated after their account's close date. A
/// closed account should have none, so they suggest the close date is wrong.
/// Shared by the slices that flag them. See decision 4 in
/// docs/reports.md.</summary>
module TransactionsAfterCloseQuery =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data.Db

    /// <summary>The account and date of each of the user's transactions dated
    /// after its account's close date. Transactions on the close date are the
    /// account's last, so they are not included.</summary>
    let read
        (ctx : QueryContext)
        (userId : string)
        : Task<(Guid * DateOnly) list> =
        task {
            let! rows =
                selectTask ctx {
                    for t in main.Transactions do
                        join a in main.Accounts on (t.AccountId = Some a.Id)

                        where (
                            t.UserId = userId
                            && a.UserId = userId
                            && Some t.Date > a.ClosedOn
                        )

                        select (a.Id, t.Date)
                }

            return List.ofSeq rows
        }
