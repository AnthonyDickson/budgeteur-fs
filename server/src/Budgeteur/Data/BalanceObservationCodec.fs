namespace Budgeteur.Data

module BalanceObservationCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account
    open Budgeteur.Domain.Money

    let toRow
        (accountId : Guid)
        (userId : string)
        (observation : BalanceObservation)
        : main.BalanceObservations = {
        AccountId = accountId
        UserId = userId
        AsOf = observation.AsOf
        Balance = Money.value observation.Balance
    }

    let fromRow (row : main.BalanceObservations) : BalanceObservation = {
        AsOf = row.AsOf
        Balance = Money.unsafeFromDecimal row.Balance
    }
