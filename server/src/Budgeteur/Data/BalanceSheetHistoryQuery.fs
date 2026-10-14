namespace Budgeteur.Data

/// <summary>Reads every item and account a user has with their observations,
/// what a balance sheet for any statement date is drawn from. Shared by the
/// slices that draw one.</summary>
module BalanceSheetHistoryQuery =
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheet

    /// <summary>The user's items and accounts, open or closed, each with its
    /// observations. A user's observations are few enough to load at
    /// once.</summary>
    let read
        (queryContext : QueryContextFactory)
        (userId : string)
        : Task<BalanceSheetHistory> =
        task {
            let! items =
                selectTask queryContext {
                    for i in main.BalanceSheetItems do
                        where (i.UserId = userId)
                }

            and! itemObservations =
                selectTask queryContext {
                    for o in main.ItemObservations do
                        where (o.UserId = userId)
                }

            and! accounts =
                selectTask queryContext {
                    for a in main.Accounts do
                        where (a.UserId = userId)
                        orderBy a.Name
                }

            and! balanceObservations =
                selectTask queryContext {
                    for o in main.BalanceObservations do
                        where (o.UserId = userId)
                }

            let itemObservationsById =
                itemObservations |> Seq.groupBy _.ItemId |> Map.ofSeq

            let balanceObservationsById =
                balanceObservations |> Seq.groupBy _.AccountId |> Map.ofSeq

            let observationsOf ids id decode =
                Map.tryFind id ids
                |> Option.map (Seq.map decode >> List.ofSeq)
                |> Option.defaultValue []

            return {
                ItemHistories =
                    items
                    |> Seq.map (fun row ->
                        BalanceSheetItemCodec.fromRow row,
                        observationsOf
                            itemObservationsById
                            row.Id
                            ItemObservationCodec.fromRow)
                    |> List.ofSeq
                AccountHistories =
                    accounts
                    |> Seq.map (fun row ->
                        AccountCodec.fromRow row,
                        observationsOf
                            balanceObservationsById
                            row.Id
                            BalanceObservationCodec.fromRow)
                    |> List.ofSeq
            }
        }
