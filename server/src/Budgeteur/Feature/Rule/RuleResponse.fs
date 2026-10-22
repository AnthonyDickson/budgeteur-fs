namespace Budgeteur.Feature.Rule

open System

open Budgeteur.Domain.Rule
open Budgeteur.Shared.OpenApi

type RuleResponse = {
    Id : Guid
    Pattern : string

    /// <summary>What the rule proposes when it wins. A tag rule's tag is
    /// applied by auto-tagging; a transfer rule's transfer is only suggested
    /// in quick tagging.</summary>
    [<SchemaHint.Enum(typeof<RuleTarget>)>]
    Target : string

    /// <summary>The tag a tag rule proposes. Absent for a transfer
    /// rule.</summary>
    TagId : Guid option
}

module RuleResponse =
    let fromDomain (rule : Rule) : RuleResponse = {
        Id = rule.Id
        Pattern = RulePattern.value rule.Pattern
        Target = RuleTarget.kind rule.Target
        TagId = RuleTarget.tagId rule.Target
    }
