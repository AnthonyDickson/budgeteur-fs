namespace Budgeteur.Feature.Rule

module Rule =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Rule

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
