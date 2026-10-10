namespace Budgeteur.Feature.Tag

open System

open Budgeteur.Domain.Tag
open Budgeteur.Shared.OpenApi

type TagResponse = {
    Id : Guid
    Name : string
    Color : string

    /// <summary>Which side of the income statement the tag's transactions are
    /// on.</summary>
    [<SchemaHint.Enum(typeof<TagKind>)>]
    Kind : string
}

module TagResponse =
    let fromDomain (tag : Tag) : TagResponse = {
        Id = tag.Id
        Name = TagName.value tag.Name
        Color = TagColor.value tag.Color
        Kind = TagKind.toString tag.Kind
    }
