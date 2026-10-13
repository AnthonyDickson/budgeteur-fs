namespace Budgeteur.Tests.AutoTag

module ChangesTests =
    open System
    open Expecto

    open Budgeteur.Domain.Rule
    open Budgeteur.Domain.Categorisation
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.AutoTag

    let private groceries = Guid.CreateVersion7 ()
    let private fuel = Guid.CreateVersion7 ()
    let private dining = Guid.CreateVersion7 ()

    let private rule (pattern : string) (tagId : Guid) : Rule = {
        Id = Guid.CreateVersion7 ()
        Pattern = RulePattern.unsafeFromString pattern
        TagId = tagId
    }

    let private rules = [
        rule "COUNTDOWN" groceries
        rule "COUNTDOWN FUEL" fuel
    ]

    let private candidate description categorisation = {
        TransactionId = Guid.CreateVersion7 ()
        Description = TransactionDescription.unsafeFromString description
        Categorisation = categorisation
    }

    let private ruleTag tagId =
        Categorisation.Tagged (tagId, TagSource.Rule)

    let private untaggedMatch = candidate "PAY Countdown Ponsonby" None
    let private untaggedNoMatch = candidate "Rent" None
    // The fuel rule now wins over the groceries tag a rule set earlier.
    let private staleRuleTag =
        candidate "Countdown Fuel" (Some (ruleTag groceries))

    let private orphanRuleTag = candidate "Pak'nSave" (Some (ruleTag groceries))

    let private currentRuleTag =
        candidate "Countdown" (Some (ruleTag groceries))

    let private manualTag =
        candidate
            "Countdown Fuel"
            (Some (Categorisation.Tagged (dining, TagSource.Manual)))

    let private all = [
        untaggedMatch
        untaggedNoMatch
        staleRuleTag
        orphanRuleTag
        currentRuleTag
        manualTag
    ]

    [<Tests>]
    let tests =
        testList "AutoTag.changes" [
            testCase "TagUntagged only tags untagged transactions"
            <| fun () ->
                Expect.equal
                    (AutoTag.changes TagUntagged rules all)
                    [ Tagged (untaggedMatch.TransactionId, ruleTag groceries) ]
                    "only the untagged match should change"

            testCase "Retag tags, changes, and clears rule tags"
            <| fun () ->
                Expect.equal
                    (AutoTag.changes Retag rules all)
                    [
                        Tagged (untaggedMatch.TransactionId, ruleTag groceries)
                        Changed (staleRuleTag.TransactionId, ruleTag fuel)
                        Cleared orphanRuleTag.TransactionId
                    ]
                    "unchanged rule tags and manual tags should not change"

            testCase "counts each kind of change"
            <| fun () ->
                Expect.equal
                    (AutoTag.counts (AutoTag.changes Retag rules all))
                    { Tagged = 1; Changed = 1; Cleared = 1 }
                    "each kind should be counted once"
        ]
