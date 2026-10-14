namespace Budgeteur.Feature.BalanceSheet

/// <summary>Reads the slice's handlers share: items with their current value,
/// and the uniqueness check.</summary>
module ItemQuery =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem

    /// <summary>The user's items with their current values.</summary>
    let readAll (ctx : QueryContext) (userId : string) : Task<ItemValue list> =
        task {
            let! rows =
                selectTask ctx {
                    for item in main.BalanceSheetItems do
                        join current in main.CurrentItemValues
                                            on
                                            (Some item.Id = current.ItemId)

                        where (item.UserId = userId)
                        select (item, current)
                }

            return rows |> Seq.map ItemValueCodec.fromRow |> List.ofSeq
        }

    /// <summary>The user's item with its current value, if the user has one
    /// with the id.</summary>
    let tryRead
        (ctx : QueryContext)
        (userId : string)
        (id : Guid)
        : Task<ItemValue option> =
        task {
            let! row =
                selectTask ctx {
                    for item in main.BalanceSheetItems do
                        join current in main.CurrentItemValues
                                            on
                                            (Some item.Id = current.ItemId)

                        where (item.Id = id && item.UserId = userId)
                        select (item, current)
                        tryHead
                }

            return Option.map ItemValueCodec.fromRow row
        }

    /// <summary>Verify that no other item of the user has the item's name,
    /// side, and term, mirroring the <c>UNIQUE(UserId, Name, Side, Term)</c>
    /// constraint.</summary>
    let requireIsUnique
        (queryContext : QueryContextFactory)
        (userId : string)
        (item : BalanceSheetItem)
        : Task<Result<unit, ConstraintError>> =
        task {
            let item = BalanceSheetItemCodec.toRow item userId

            let! rowCount =
                selectTask queryContext {
                    for row in main.BalanceSheetItems do
                        where (
                            row.Id <> item.Id
                            && row.UserId = userId
                            && row.Name = item.Name
                            && row.Side = item.Side
                            && row.Term = item.Term
                        )

                        count
                }

            return
                if rowCount = 0 then
                    Ok ()
                else
                    Error (
                        ConstraintError
                            "An identical balance sheet item already exists."
                    )
        }
