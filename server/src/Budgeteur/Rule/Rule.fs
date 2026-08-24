namespace Budgeteur.Rule

open System

type Rule = {
    Id : Guid
    Pattern : string
    TagId : Guid
}

module Rule =
    open Budgeteur.Db

    let toRow (rule : Rule) (userId : string) : main.Rules = {
        Id = rule.Id
        UserId = userId
        Pattern = rule.Pattern
        TagId = rule.TagId
    }

    let fromRow (row : main.Rules) : Rule = {
        Id = row.Id
        Pattern = row.Pattern
        TagId = row.TagId
    }
