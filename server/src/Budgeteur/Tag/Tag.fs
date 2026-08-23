namespace Budgeteur.Tag

open System

type Tag = { Id : Guid; Name : string }

module Tag =
    open Budgeteur.Db

    let toRow (tag : Tag) (userId : string) : main.Tags = {
        Id = tag.Id
        Name = tag.Name
        UserId = userId
    }

    let fromRow (row : main.Tags) : Tag = { Id = row.Id; Name = row.Name }
