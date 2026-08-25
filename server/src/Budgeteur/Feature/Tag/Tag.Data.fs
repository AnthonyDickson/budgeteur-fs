namespace Budgeteur.Feature.Tag

module Tag =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Tag

    let toRow (tag : Tag) (userId : string) : main.Tags = {
        Id = tag.Id
        Name = tag.Name
        UserId = userId
    }

    let fromRow (row : main.Tags) : Tag = { Id = row.Id; Name = row.Name }
