namespace Budgeteur.Feature.Tag

open System

type TagResponse = { Id : Guid; Name : string }

module TagResponse =
    open Budgeteur.Domain.Tag

    let fromDomain (tag : Tag) : TagResponse = {
        Id = tag.Id
        Name = TagName.value tag.Name
    }
