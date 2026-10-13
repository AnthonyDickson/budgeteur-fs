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

    /// <summary>The user's accounts with their current balances, by
    /// name.</summary>
    let readAll (ctx : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask ctx {
                    for a in main.Accounts do
                        leftJoin' c in main.LeftJoined.CurrentBalances
                        on' (Some a.Id = c.AccountId)

                        where (a.UserId = userId)
                        orderBy a.Name
                        select (a, c)
                }

            return rows |> Seq.map AccountBalanceCodec.fromRow |> List.ofSeq
        }

    /// <summary>The user's account with its current balance, if the user has
    /// one with the id.</summary>
    let tryRead (ctx : QueryContext) (userId : string) (id : Guid) =
        task {
            let! row =
                selectTask ctx {
                    for a in main.Accounts do
                        leftJoin' c in main.LeftJoined.CurrentBalances
                        on' (Some a.Id = c.AccountId)

                        where (a.Id = id && a.UserId = userId)
                        select (a, c)
                        tryHead
                }

            return Option.map AccountBalanceCodec.fromRow row
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
