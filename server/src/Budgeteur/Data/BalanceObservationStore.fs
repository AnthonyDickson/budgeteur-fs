namespace Budgeteur.Data

/// <summary>Writes balance observations. Every slice that records a balance
/// writes through here, so a new observation replaces any on its date the same
/// way, whether it came from a statement or was entered by hand.</summary>
module BalanceObservationStore =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query
    open SqlHydra.Query.SqliteExtensions

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account

    /// <summary>Record the account's balance as of the observation's date,
    /// replacing any observation on that date. The caller checks that the
    /// account belongs to the user.</summary>
    let record
        (queryContext : QueryContext)
        (userId : string)
        (accountId : Guid)
        (observation : BalanceObservation)
        : Task<unit> =
        task {
            let row = BalanceObservationCodec.toRow accountId userId observation

            let! _ =
                insertTask queryContext {
                    for o in main.BalanceObservations do
                        entity row
                        onConflictDoUpdate (o.AccountId, o.AsOf) o.Balance
                }

            ()
        }
