namespace Budgeteur.Data

module TagCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Tag

    let toRow (tag : Tag) (userId : string) : main.Tags = {
        Id = tag.Id
        Name = TagName.value tag.Name
        UserId = userId
        Color = TagColor.toString tag.Color
        Kind = TagKind.toString tag.Kind
    }

    let fromRow (row : main.Tags) : Tag = {
        Id = row.Id
        Name = TagName.unsafeFromString row.Name
        Color =
            match TagColor.parse row.Color with
            | Ok color -> color
            // Only the tag endpoints write this column, and they parse it first
            | Error error -> failwith error
        Kind =
            match TagKind.parse row.Kind with
            | Ok kind -> kind
            // The database checks this column, so in practice this arm is
            // unreachable
            | Error error -> failwith error
    }
