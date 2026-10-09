namespace Budgeteur.Data

module TagCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Tag

    let toRow (tag : Tag) (userId : string) : main.Tags = {
        Id = tag.Id
        Name = TagName.value tag.Name
        UserId = userId
        Color = TagColor.value tag.Color
        Kind = TagKind.toString tag.Kind
    }

    let fromRow (row : main.Tags) : Tag = {
        Id = row.Id
        Name = TagName.unsafeFromString row.Name
        Color = TagColor.unsafeFromString row.Color
        Kind =
            match TagKind.parse row.Kind with
            | Ok kind -> kind
            // The database checks this column, so in practice this arm is unreachable
            | Error error -> failwith error
    }
