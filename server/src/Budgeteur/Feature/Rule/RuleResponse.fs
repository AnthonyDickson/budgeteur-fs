namespace Budgeteur.Feature.Rule

open System

type RuleResponse = {
    Id : Guid
    Pattern : string
    TagId : Guid
}

module RuleResponse =
    open Budgeteur.Domain.Rule

    let fromDomain (rule : Rule) : RuleResponse = {
        Id = rule.Id
        Pattern = RulePattern.value rule.Pattern
        TagId = rule.TagId
    }
