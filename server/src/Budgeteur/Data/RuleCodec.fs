namespace Budgeteur.Data

module RuleCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Rule

    /// <summary>The target is stored as its kind and tag id; the schema checks
    /// that a row has a tag id exactly when it is a tag rule.</summary>
    let toRow (rule : Rule) (userId : string) : main.Rules = {
        Id = rule.Id
        UserId = userId
        Pattern = RulePattern.value rule.Pattern
        Target = RuleTarget.kind rule.Target
        TagId = RuleTarget.tagId rule.Target
    }

    let fromRow (row : main.Rules) : Rule = {
        Id = row.Id
        Pattern = RulePattern.unsafeFromString row.Pattern
        Target =
            // The database checks these columns, so in practice the error is
            // unreachable.
            match RuleTarget.create row.Target row.TagId with
            | Ok target -> target
            | Error error -> failwith $"Invalid rule target: %A{error}"
    }
