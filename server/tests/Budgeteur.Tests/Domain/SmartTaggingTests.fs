namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.Categorisation
open Budgeteur.Domain.Money
open Budgeteur.Domain.Rule
open Budgeteur.Domain.SmartTagging
open Budgeteur.Domain.Transaction

module SmartTaggingTests =
    let private account = Guid.NewGuid ()
    let private groceries = RuleTarget.Tag (Guid.NewGuid ())
    let private eatingOut = RuleTarget.Tag (Guid.NewGuid ())
    let private gifts = RuleTarget.Tag (Guid.NewGuid ())

    let private transaction (description : string) (amount : decimal) = {
        Id = Guid.NewGuid ()
        Amount = Money.create amount
        Description = TransactionDescription.unsafeFromString description
        Date = DateOnly (2026, 1, 1)
        AccountId = Some account
    }

    let private label target description amount = {
        Transaction = transaction description amount
        Class = target
        Weight = 1.0
    }

    /// Two classes, each a merchant seen often, with varied amounts.
    let private twoMerchants =
        [
            for i in 1..15 ->
                label groceries "FRESH MART HIGHLAND PARK" (-20m * decimal i)
        ]
        @ [
            for i in 1..15 ->
                label eatingOut "HARBOUR CAFE AUCKLAND" (-2m * decimal i)
        ]

    [<Tests>]
    let tests =
        testList "SmartTagging" [
            testCase "labels come from the user's decisions, weighted by source"
            <| fun () ->
                let tagId = Guid.NewGuid ()
                let row = transaction "FRESH MART" -10m

                let weightOf categorisation =
                    Label.ofCategorisation row categorisation
                    |> Option.map (fun label -> label.Class, label.Weight)

                Expect.equal
                    (weightOf (Categorisation.Tagged (tagId, Source.Manual)))
                    (Some (RuleTarget.Tag tagId, 1.0))
                    "manual"

                Expect.equal
                    (weightOf (Categorisation.Tagged (tagId, Source.Accepted)))
                    (Some (RuleTarget.Tag tagId, 0.5))
                    "accepted"

                Expect.equal
                    (weightOf (Categorisation.Transfer Source.Detected))
                    (Some (RuleTarget.Transfer, 1.0))
                    "detected transfer"

                Expect.isNone
                    (weightOf (Categorisation.Tagged (tagId, Source.Rule)))
                    "rule tags are not labels"

                Expect.isNone
                    (weightOf Categorisation.Dismissed)
                    "a dismissal is not a class"

            testCase
                "class balance takes the square root factor and keeps the total"
            <| fun () ->
                let labels =
                    List.replicate 9 (label groceries "FRESH MART" -10m)
                    @ [ label gifts "GIFT SHOP" -10m ]

                let balanced = ClassBalance.balance labels

                let classTotal target =
                    balanced
                    |> List.filter (fun l -> l.Class = target)
                    |> List.sumBy _.Weight

                Expect.floatClose
                    Accuracy.veryHigh
                    (balanced |> List.sumBy _.Weight)
                    10.0
                    "the total weight is kept"

                // The factors are 10 / (2 * 9) and 10 / (2 * 1), whose square
                // roots are in the ratio 1 to 3, so the small class's total
                // goes from a ninth of the large class's to a third.
                Expect.floatClose
                    Accuracy.veryHigh
                    (classTotal gifts / classTotal groceries)
                    (1.0 / 3.0)
                    "the small class counts for more"

            testCase "too few labels abstain"
            <| fun () ->
                let model = Model.fit (List.take 24 twoMerchants)

                Expect.equal
                    (Model.predict model (transaction "FRESH MART" -30m))
                    (Prediction.Abstain (AbstainReason.TooFewLabels 24))
                    "fewer than 25 labels"

            testCase "a confident prediction is a proposal"
            <| fun () ->
                let model = Model.fit twoMerchants

                match
                    Model.predict
                        model
                        (transaction "FRESH MART GLEN EDEN" -45m)
                with
                | Prediction.Proposal (target, confidence) ->
                    Expect.equal target groceries "the merchant's tag"

                    Expect.isGreaterThanOrEqual
                        confidence
                        Model.Threshold
                        "confident"
                | other -> failtestf "expected a proposal, got %A" other

            testCase "an unfamiliar transaction abstains for low confidence"
            <| fun () ->
                let model = Model.fit twoMerchants

                match Model.predict model (transaction "QQQ" -10m) with
                | Prediction.Abstain (AbstainReason.LowConfidence confidence) ->
                    Expect.isLessThan
                        confidence
                        Model.Threshold
                        "below the threshold"
                | other -> failtestf "expected low confidence, got %A" other

            testCase "a class with one label is never proposed"
            <| fun () ->
                let model =
                    Model.fit (
                        label gifts "ZEBRA TOYS XYLOPHONE" 500m :: twoMerchants
                    )

                Expect.equal
                    (Model.predict
                        model
                        (transaction "ZEBRA TOYS XYLOPHONE" 500m))
                    (Prediction.Abstain (AbstainReason.RareClass (gifts, 1)))
                    "the top class has one label"

            testCase "the order of the labels does not change the model"
            <| fun () ->
                let row = transaction "FRESH CAFE" -15m

                let probabilities labels =
                    Model.probabilities (Model.fit labels) row

                Expect.equal
                    (probabilities twoMerchants)
                    (probabilities (List.rev twoMerchants))
                    "the same probabilities"
        ]
