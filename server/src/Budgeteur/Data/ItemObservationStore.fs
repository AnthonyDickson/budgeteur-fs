namespace Budgeteur.Data

/// <summary>Writes item observations, so a new observation replaces any on its
/// date the same way whichever operation records it.</summary>
module ItemObservationStore =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query
    open SqlHydra.Query.SqliteExtensions

    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem

    /// <summary>Record the item's value as of the observation's date, replacing
    /// any observation on that date. The caller checks that the item belongs
    /// to the user.</summary>
    let record
        (queryContext : QueryContext)
        (userId : string)
        (itemId : Guid)
        (observation : ItemObservation)
        : Task<unit> =
        task {
            let row = ItemObservationCodec.toRow itemId userId observation

            let! _ =
                insertTask queryContext {
                    for o in main.ItemObservations do
                        entity row
                        onConflictDoUpdate (o.ItemId, o.AsOf) o.Value
                }

            ()
        }
