namespace Budgeteur.Tests.QuickTag

module SuggestionTests =
    open System
    open Expecto

    open Budgeteur.Domain.Rule
    open Budgeteur.Domain.Tag
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.QuickTag

    let private tag name kind : Tag = {
        Id = Guid.CreateVersion7 ()
        Name = TagName.create name |> Result.defaultWith (failtestf "%A")
        Color = TagColor.Green
        Kind = kind
    }

    let private salary = tag "Salary" Income
    let private groceries = tag "Groceries" Expense
    let private dining = tag "Dining" Expense

    let private rule pattern target : Rule = {
        Id = Guid.CreateVersion7 ()
        Pattern = RulePattern.unsafeFromString pattern
        Target = target
    }

    let private rules = [
        rule "TO SAVINGS" RuleTarget.Transfer
        rule "ASB CARD" RuleTarget.Transfer
        rule "COUNTDOWN" (RuleTarget.Tag groceries.Id)
        rule "CAFE" (RuleTarget.Tag dining.Id)
        rule "PAYROLL" (RuleTarget.Tag salary.Id)
    ]

    /// Newest first, as the queue is read.
    let private queue = [
        "PAYROLL ACME"
        "TRANSFER TO SAVINGS"
        "Countdown Ponsonby"
        "ASB CARD 1234"
        "Rent"
        "Cafe Hanoi"
        "COUNTDOWN METRO"
    ]

    let private read filter batchSize =
        Suggestion.readQueue
            batchSize
            rules
            [ salary; groceries; dining ]
            TransactionDescription.unsafeFromString
            filter
            queue

    let private patterns (batch : QueueBatch<string>) =
        batch.Batch
        |> List.map (fun row ->
            row.Transaction,
            row.Suggestion |> Option.map (_.Pattern >> RulePattern.value))

    [<Tests>]
    let tests =
        testList "Suggestion.readQueue" [
            testCase "each row is suggested the winning rule's target"
            <| fun () ->
                let read = read None 50

                Expect.equal
                    (patterns read)
                    [
                        "PAYROLL ACME", Some "PAYROLL"
                        "TRANSFER TO SAVINGS", Some "TO SAVINGS"
                        "Countdown Ponsonby", Some "COUNTDOWN"
                        "ASB CARD 1234", Some "ASB CARD"
                        "Rent", None
                        "Cafe Hanoi", Some "CAFE"
                        "COUNTDOWN METRO", Some "COUNTDOWN"
                    ]
                    "the winning pattern, or none when no rule matches"

                Expect.equal
                    (read.Batch
                     |> List.choose (_.Suggestion >> Option.map _.Target))
                    [
                        RuleTarget.Tag salary.Id
                        RuleTarget.Transfer
                        RuleTarget.Tag groceries.Id
                        RuleTarget.Transfer
                        RuleTarget.Tag dining.Id
                        RuleTarget.Tag groceries.Id
                    ]
                    "the winning target"

            testCase "counts cover the whole queue, in button order"
            <| fun () ->
                Expect.equal
                    (read None 2).Counts
                    [
                        RuleTarget.Tag dining.Id, 1
                        RuleTarget.Tag groceries.Id, 2
                        RuleTarget.Tag salary.Id, 1
                        RuleTarget.Transfer, 2
                    ]
                    "expense tags then income tags by name, then transfers \
                    from both rules together"

            testCase "the filter keeps the rows suggested its target"
            <| fun () ->
                let read = read (Some RuleTarget.Transfer) 1

                Expect.equal
                    (patterns read)
                    [ "TRANSFER TO SAVINGS", Some "TO SAVINGS" ]
                    "a batch of the rows suggested a transfer"

                Expect.equal read.Total 2 "the total counts the filtered rows"

                Expect.equal
                    (List.length read.Counts)
                    4
                    "the counts still cover the whole queue"

            testCase "without a filter the total is the whole queue"
            <| fun () ->
                let read = read None 2
                Expect.hasLength read.Batch 2 "a batch"
                Expect.equal read.Total 7 "every queued transaction"
        ]
