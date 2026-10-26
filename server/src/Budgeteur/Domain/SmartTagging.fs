namespace Budgeteur.Domain.SmartTagging

open Budgeteur.Domain.Categorisation
open Budgeteur.Domain.LogisticRegression
open Budgeteur.Domain.Rule
open Budgeteur.Domain.Transaction
open Budgeteur.Domain.Vectoriser

/// <summary>A transaction the model learns from, with its class (one of the
/// user's tags, or transfer) and its weight. See decision 4 in
/// docs/smart-tagging.md.</summary>
type Label = {
    Transaction : Transaction
    Class : RuleTarget
    Weight : float
}

module Label =
    /// <summary>A label's weight by the source of its categorisation:
    /// <c>Manual</c> and <c>Detected</c> in full, <c>Accepted</c> at half,
    /// since it confirms a suggestion, sometimes in bulk. <c>Rule</c>
    /// categorisations are not labels.</summary>
    let weight (source : Source) : float option =
        match source with
        | Source.Manual
        | Source.Detected -> Some 1.0
        | Source.Accepted -> Some 0.5
        | Source.Rule -> None

    /// <summary>The label a categorisation gives its transaction, if any. A
    /// dismissal says the transaction has no tag, so it is not a
    /// class.</summary>
    let ofCategorisation
        (transaction : Transaction)
        (categorisation : Categorisation)
        : Label option =
        let label target source =
            weight source
            |> Option.map (fun weight -> {
                Transaction = transaction
                Class = target
                Weight = weight
            })

        match categorisation with
        | Categorisation.Tagged (tagId, source) ->
            label (RuleTarget.Tag tagId) source
        | Categorisation.Transfer source -> label RuleTarget.Transfer source
        | Categorisation.Dismissed -> None

/// <summary>Square root class balance: each label's weight times the square
/// root of its class's balancing factor, the total weight over the number of
/// classes times the class's own total. The weights are then scaled back to
/// their original total, so the regularisation strength means the same. See
/// decision 4 in docs/smart-tagging.md.</summary>
module ClassBalance =
    let balance (labels : Label list) : Label list =
        let total = labels |> List.sumBy _.Weight

        let classTotals =
            labels
            |> List.groupBy _.Class
            |> List.map (fun (target, labels) ->
                target, labels |> List.sumBy _.Weight)
            |> Map.ofList

        let factor target =
            sqrt (total / (float classTotals.Count * classTotals[target]))

        let scaled =
            labels
            |> List.map (fun label -> {
                label with
                    Weight = label.Weight * factor label.Class
            })

        let rescale = total / (scaled |> List.sumBy _.Weight)

        scaled
        |> List.map (fun label -> {
            label with
                Weight = label.Weight * rescale
        })

/// <summary>Why the model makes no suggestion for a transaction. See decision
/// 7 in docs/smart-tagging.md.</summary>
[<RequireQualifiedAccess>]
type AbstainReason =
    /// <summary>The model's probability for its top class is below the
    /// threshold.</summary>
    | LowConfidence of confidence : float
    /// <summary>The user has too few labels for the model to be
    /// fitted.</summary>
    | TooFewLabels of labels : int
    /// <summary>The top class has too few labels to be suggested.</summary>
    | RareClass of target : RuleTarget * labels : int

/// <summary>What the model proposes for a transaction.</summary>
[<RequireQualifiedAccess>]
type Prediction =
    /// <summary>The model's proposal, with its probability.</summary>
    | Proposal of target : RuleTarget * confidence : float
    | Abstain of AbstainReason

type private Fitted = {
    Vectoriser : Vectoriser
    Classifier : Classifier<RuleTarget>
    /// <summary>Labels by class, for the per-class minimum.</summary>
    ClassLabels : Map<RuleTarget, int>
}

/// <summary>The model fitted to a user's labels, or the count of too few
/// labels to fit.</summary>
type Model =
    private
    | Unfitted of labels : int
    | Fitted of Fitted

/// <summary>The smart tagging model: decision 3's features, decision 4's class
/// balance, and decision 2's logistic regression, with decision 7's abstaining.
/// See docs/smart-tagging.md.</summary>
module Model =
    /// <summary>The confidence below which the model abstains.</summary>
    [<Literal>]
    let Threshold = 0.7

    /// <summary>The fewest labels the model is fitted with.</summary>
    [<Literal>]
    let MinLabels = 25

    /// <summary>The fewest labels a class needs to be suggested. Classes with
    /// fewer stay in the fit, so their probability is not given to other
    /// classes.</summary>
    [<Literal>]
    let MinClassLabels = 2

    /// <summary>Fit the model to the labels. Labels are ordered by transaction
    /// id first, so the same labels in any order give the same
    /// model.</summary>
    let fit (labels : Label list) : Model =
        let count = List.length labels

        let fitted =
            if count < MinLabels then
                None
            else
                let labels =
                    labels
                    |> List.sortBy _.Transaction.Id
                    |> ClassBalance.balance

                let vectoriser =
                    Vectoriser.fit (labels |> List.map _.Transaction)

                labels
                |> List.map (fun label -> {
                    Features =
                        Vectoriser.transform vectoriser label.Transaction
                    Class = label.Class
                    Weight = label.Weight
                })
                |> LogisticRegression.fit
                    (Vectoriser.features vectoriser).Length
                |> Option.map (fun classifier -> {
                    Vectoriser = vectoriser
                    Classifier = classifier
                    ClassLabels = labels |> List.countBy _.Class |> Map.ofList
                })

        match fitted with
        | Some fitted -> Fitted fitted
        | None -> Unfitted count

    /// <summary>Each class's probability for the transaction, in class order.
    /// Empty when the model is not fitted.</summary>
    let probabilities
        (model : Model)
        (transaction : Transaction)
        : (RuleTarget * float) array =
        match model with
        | Unfitted _ -> [||]
        | Fitted fitted ->
            Vectoriser.transform fitted.Vectoriser transaction
            |> LogisticRegression.probabilities fitted.Classifier

    /// <summary>The model's proposal for the transaction, or why it
    /// abstains.</summary>
    let predict (model : Model) (transaction : Transaction) : Prediction =
        match model with
        | Unfitted labels ->
            Prediction.Abstain (AbstainReason.TooFewLabels labels)
        | Fitted fitted ->
            let target, confidence =
                Vectoriser.transform fitted.Vectoriser transaction
                |> LogisticRegression.predict fitted.Classifier

            let labels =
                fitted.ClassLabels
                |> Map.tryFind target
                |> Option.defaultValue 0

            if labels < MinClassLabels then
                Prediction.Abstain (AbstainReason.RareClass (target, labels))
            elif confidence < Threshold then
                Prediction.Abstain (AbstainReason.LowConfidence confidence)
            else
                Prediction.Proposal (target, confidence)
