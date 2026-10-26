namespace Budgeteur.Domain.LogisticRegression

open System
open System.Numerics.Tensors

open Budgeteur.Domain.Lbfgs
open Budgeteur.Domain.Vectoriser

/// <summary>A row of the training set: its features, its class, and its
/// weight in the fit.</summary>
type Example<'Class> = {
    Features : FeatureVector
    Class : 'Class
    Weight : float
}

/// <summary>The training set as the objective reads it: every row's features
/// in one run of columns and values, with each row's class as its index in the
/// class order.</summary>
type internal Problem = {
    ClassCount : int
    /// <summary>Where each row's features start in <c>Features</c>, with the
    /// total last.</summary>
    RowStarts : int array
    Features : FeatureVector
    Labels : int array
    Weights : float array
    TotalWeight : float
}

/// <summary>A fitted classifier over its classes, ordered by
/// comparison.</summary>
type Classifier<'Class> =
    private
    /// <summary>A training set with a single class predicts it with full
    /// confidence, since a softmax cannot be fitted to it.</summary>
    | Single of 'Class
    /// <summary>The coefficients by feature, then class, followed by the
    /// intercepts.</summary>
    | Multinomial of classes : 'Class array * parameters : float array

/// <summary>Weighted multinomial logistic regression with L2 regularisation,
/// as scikit-learn's <c>LogisticRegression</c> fits it with the experiments'
/// settings. See decision 2 in docs/smart-tagging.md.</summary>
/// <remarks>The numerical loops update arrays in place for speed; every
/// function is still pure.</remarks>
module LogisticRegression =
    /// <summary>Inverse regularisation strength, scikit-learn's default.
    /// Intercepts are not penalised.</summary>
    [<Literal>]
    let C = 1.0

    /// <summary>The fit stops when every component of the gradient of the
    /// objective, divided by the total weight as scikit-learn divides it, is
    /// within this. Ten times tighter than the scikit-learn default the
    /// experiments used.</summary>
    [<Literal>]
    let GradientTolerance = 1e-5

    /// <summary>Corrections L-BFGS keeps, scikit-learn's default.</summary>
    [<Literal>]
    let Memory = 10

    /// <summary>The most iterations a fit runs, whether or not it has
    /// converged.</summary>
    [<Literal>]
    let MaxIterations = 1000

    /// <summary>Each class's score for the features from <c>first</c> up to
    /// <c>last</c>: its intercept plus the features times their
    /// coefficients. Written to <c>scores</c>.</summary>
    let private score
        (classes : int)
        (parameters : float array)
        (features : FeatureVector)
        (first : int)
        (last : int)
        (scores : float array)
        =
        Array.blit parameters (parameters.Length - classes) scores 0 classes

        for entry in first .. last - 1 do
            let offset = features.Columns[entry] * classes
            let value = features.Values[entry]

            for k in 0 .. classes - 1 do
                scores[k] <- scores[k] + value * parameters[offset + k]

    /// <summary>Replaces the scores with their softmax, and returns the log
    /// of the sum of their exponentials. Both are shifted by the largest score
    /// so they neither overflow nor underflow.</summary>
    let private softmax (scores : float array) =
        let largest = TensorPrimitives.Max (ReadOnlySpan scores)
        let mutable total = 0.0

        for k in 0 .. scores.Length - 1 do
            scores[k] <- exp (scores[k] - largest)
            total <- total + scores[k]

        for k in 0 .. scores.Length - 1 do
            scores[k] <- scores[k] / total

        largest + log total

    /// <summary>The weighted cross entropy of the rows plus the L2 penalty on
    /// the coefficients, divided by the total weight. Writes its gradient,
    /// divided the same way, to <c>gradient</c>.</summary>
    let internal objective
        (problem : Problem)
        (parameters : float array)
        (gradient : float array)
        : float =
        let classes = problem.ClassCount
        let features = problem.Features
        let coefficients = parameters.Length - classes
        let penalised = ReadOnlySpan (parameters, 0, coefficients)

        // The penalty and its gradient; intercepts are not penalised.
        let mutable loss =
            TensorPrimitives.Dot (penalised, penalised) / (2.0 * C)

        TensorPrimitives.Multiply (penalised, 1.0 / C, Span gradient)
        Array.fill gradient coefficients classes 0.0
        let scores = Array.zeroCreate classes

        for row in 0 .. problem.Labels.Length - 1 do
            let first, last = problem.RowStarts[row], problem.RowStarts[row + 1]
            score classes parameters features first last scores
            let label = problem.Labels[row]
            let weight = problem.Weights[row]
            let labelScore = scores[label]
            loss <- loss + weight * (softmax scores - labelScore)

            // The probabilities become the residuals: the weighted probability
            // less the indicator of the row's class.
            for k in 0 .. classes - 1 do
                scores[k] <- weight * scores[k]

            scores[label] <- scores[label] - weight

            for entry in first .. last - 1 do
                let offset = features.Columns[entry] * classes
                let value = features.Values[entry]

                for k in 0 .. classes - 1 do
                    gradient[offset + k] <-
                        gradient[offset + k] + value * scores[k]

            for k in 0 .. classes - 1 do
                gradient[coefficients + k] <-
                    gradient[coefficients + k] + scores[k]

        let totalWeight = problem.TotalWeight

        TensorPrimitives.Multiply (
            ReadOnlySpan gradient,
            1.0 / totalWeight,
            Span gradient
        )

        loss / totalWeight

    /// <summary>The problem for rows of features, class index, and
    /// weight.</summary>
    let internal problem
        (classes : int)
        (rows : (FeatureVector * int * float) list)
        : Problem =
        let features = rows |> List.map (fun (features, _, _) -> features)

        {
            ClassCount = classes
            RowStarts =
                features
                |> List.scan (fun start row -> start + row.Columns.Length) 0
                |> Array.ofList
            Features = {
                Columns = features |> Array.ofList |> Array.collect _.Columns
                Values = features |> Array.ofList |> Array.collect _.Values
            }
            Labels =
                rows |> List.map (fun (_, label, _) -> label) |> Array.ofList
            Weights =
                rows |> List.map (fun (_, _, weight) -> weight) |> Array.ofList
            TotalWeight = rows |> List.sumBy (fun (_, _, weight) -> weight)
        }

    /// <summary>Fit to the examples, whose features have columns below
    /// <c>featureCount</c>. Starts from zero with a fixed memory and iteration
    /// cap, so the same examples in the same order always give the same
    /// classifier. None without examples.</summary>
    let fit
        (featureCount : int)
        (examples : Example<'Class> list)
        : Classifier<'Class> option =
        let classes =
            examples
            |> List.map _.Class
            |> List.distinct
            |> List.sort
            |> Array.ofList

        match classes with
        | [||] -> None
        | [| single |] -> Some (Single single)
        | _ ->
            let index =
                classes |> Array.mapi (fun index c -> c, index) |> Map.ofArray

            // Rows with the same features and class are one row with their
            // total weight, which leaves the objective unchanged: recurring
            // transactions often repeat a row exactly.
            let problem =
                examples
                |> List.groupBy (fun example -> example.Features, example.Class)
                |> List.map (fun ((features, c), examples) ->
                    features, index[c], examples |> List.sumBy _.Weight)
                |> problem classes.Length

            let minimum =
                Array.zeroCreate ((featureCount + 1) * classes.Length)
                |> Lbfgs.minimise
                    GradientTolerance
                    Memory
                    MaxIterations
                    (objective problem)

            Some (Multinomial (classes, minimum.Point))

    /// <summary>Each class's probability for the features, in class
    /// order.</summary>
    let probabilities
        (classifier : Classifier<'Class>)
        (features : FeatureVector)
        : ('Class * float) array =
        match classifier with
        | Single single -> [| single, 1.0 |]
        | Multinomial (classes, parameters) ->
            let scores = Array.zeroCreate classes.Length

            score
                classes.Length
                parameters
                features
                0
                features.Columns.Length
                scores

            softmax scores |> ignore
            Array.zip classes scores

    /// <summary>The most probable class and its probability, the first in
    /// class order on a tie.</summary>
    let predict
        (classifier : Classifier<'Class>)
        (features : FeatureVector)
        : 'Class * float =
        // A classifier has at least one class, and maxBy keeps the first of
        // equal maxima.
        probabilities classifier features |> Array.maxBy snd
