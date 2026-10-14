namespace Budgeteur.Data

module ItemObservationCodec =
    open System

    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem

    let toRow
        (itemId : Guid)
        (userId : string)
        (observation : ItemObservation)
        : main.ItemObservations = {
        ItemId = itemId
        UserId = userId
        AsOf = observation.AsOf
        Value = Value.value observation.Value
    }

    let fromRow (row : main.ItemObservations) : ItemObservation = {
        AsOf = row.AsOf
        Value = Value.unsafeFromDecimal row.Value
    }
