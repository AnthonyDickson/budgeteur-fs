namespace Budgeteur.Data

module RuleCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Rule

    let toRow (rule : Rule) (userId : string) : main.Rules = {
        Id = rule.Id
        UserId = userId
        Pattern = RulePattern.value rule.Pattern
        TagId = rule.TagId
    }

    let fromRow (row : main.Rules) : Rule = {
        Id = row.Id
        Pattern = RulePattern.unsafeFromString row.Pattern
        TagId = row.TagId
    }
