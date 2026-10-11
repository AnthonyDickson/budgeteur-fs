namespace Budgeteur.Feature.Account

/// <summary>Reads the slice's handlers share: accounts with their current
/// balance, and the number uniqueness check.</summary>
module AccountQuery =
    open System
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account

    /// <summary>Pair each account with its current balance.</summary>
    let private withCurrent
        (accounts : main.Accounts seq)
        (observations : main.BalanceObservations seq)
        : (Account * BalanceObservation option) list =
        let observationsByAccount =
            observations
            |> Seq.groupBy _.AccountId
            |> Seq.map (fun (accountId, rows) ->
                accountId,
                rows |> Seq.map BalanceObservationCodec.fromRow |> List.ofSeq)
            |> Map.ofSeq

        accounts
        |> Seq.map (fun row ->
            let observations =
                observationsByAccount
                |> Map.tryFind row.Id
                |> Option.defaultValue []

            AccountCodec.fromRow row, BalanceObservation.current observations)
        |> List.ofSeq

    /// <summary>The user's accounts with their current balances, by
    /// name.</summary>
    let readAll (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! accounts =
                selectTask queryContext {
                    for a in main.Accounts do
                        where (a.UserId = userId)
                        orderBy a.Name
                }

            and! observations =
                selectTask queryContext {
                    for o in main.BalanceObservations do
                        where (o.UserId = userId)
                }

            return withCurrent accounts observations
        }

    /// <summary>The user's account with its current balance, if the user has
    /// one with the id.</summary>
    let tryRead
        (queryContext : QueryContextFactory)
        (userId : string)
        (id : Guid)
        =
        task {
            let! accounts =
                selectTask queryContext {
                    for a in main.Accounts do
                        where (a.Id = id && a.UserId = userId)
                }

            and! observations =
                selectTask queryContext {
                    for o in main.BalanceObservations do
                        where (o.AccountId = id && o.UserId = userId)
                }

            return withCurrent accounts observations |> List.tryHead
        }

    /// <summary>Verify that no other account of the user has the account's
    /// number, mirroring the <c>UNIQUE(UserId, Number)</c>
    /// constraint.</summary>
    let requireNumberIsUnique
        (queryContext : QueryContextFactory)
        (userId : string)
        (account : Account)
        : Task<Result<unit, ConstraintError>> =
        task {
            match account.Number with
            | None -> return Ok ()
            | Some number ->
                let number = AccountNumber.value number
                let column = Some number
                let id = account.Id

                let! rowCount =
                    selectTask queryContext {
                        for a in main.Accounts do
                            where (
                                a.UserId = userId
                                && a.Number = column
                                && a.Id <> id
                            )

                            count
                    }

                return
                    if rowCount = 0 then
                        Ok ()
                    else
                        Error (
                            ConstraintError
                                $"Another account already has the number \
                                {number}."
                        )
        }
