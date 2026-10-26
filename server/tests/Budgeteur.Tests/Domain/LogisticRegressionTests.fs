namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.LogisticRegression
open Budgeteur.Domain.Vectoriser

module LogisticRegressionTests =
    let private vector (entries : (int * float) list) : FeatureVector = {
        Columns = entries |> List.map fst |> Array.ofList
        Values = entries |> List.map snd |> Array.ofList
    }

    let private example features label weight = {
        Features = vector features
        Class = label
        Weight = weight
    }

    let private fitOrFail featureCount examples =
        match LogisticRegression.fit featureCount examples with
        | Some classifier -> classifier
        | None -> failtest "expected a classifier"

    let private probabilityOf label classifier features =
        LogisticRegression.probabilities classifier (vector features)
        |> Array.tryFind (fun (c, _) -> c = label)
        |> Option.map snd
        |> Option.defaultWith (fun () -> failtestf "no class %A" label)

    /// Two classes, each with its own feature, and a feature both share.
    let private separable =
        List.replicate 20 (example [ 0, 0.8; 2, 0.6 ] "a" 1.0)
        @ List.replicate 20 (example [ 1, 0.8; 2, 0.6 ] "b" 1.0)

    [<Tests>]
    let tests =
        testList "LogisticRegression" [
            testCase "the gradient matches finite differences"
            <| fun () ->
                let random = Random 7
                let featureCount, classes = 4, 3

                let rows = [
                    for _ in 1..12 ->
                        let columns =
                            [ 0 .. featureCount - 1 ]
                            |> List.filter (fun _ -> random.NextDouble () < 0.6)

                        vector (
                            columns
                            |> List.map (fun column ->
                                column, random.NextDouble ())
                        ),
                        random.Next classes,
                        0.5 + random.NextDouble ()
                ]

                let problem = LogisticRegression.problem classes rows

                let parameters =
                    Array.init (featureCount * classes + classes) (fun _ ->
                        random.NextDouble () - 0.5)

                let loss (parameters : float array) =
                    Array.zeroCreate parameters.Length
                    |> LogisticRegression.objective problem parameters

                let gradient = Array.zeroCreate parameters.Length

                LogisticRegression.objective problem parameters gradient
                |> ignore

                let step = 1e-6

                for index in 0 .. parameters.Length - 1 do
                    let shifted by =
                        parameters
                        |> Array.mapi (fun i p ->
                            if i = index then p + by else p)

                    let numeric =
                        (loss (shifted step) - loss (shifted -step))
                        / (2.0 * step)

                    Expect.floatClose
                        { absolute = 1e-8; relative = 1e-6 }
                        gradient[index]
                        numeric
                        $"partial derivative %i{index}"

            testCase "separable classes are predicted with high confidence"
            <| fun () ->
                let classifier = fitOrFail 3 separable

                Expect.equal
                    (LogisticRegression.predict classifier (vector [ 0, 1.0 ])
                     |> fst)
                    "a"
                    "a's feature"

                Expect.isGreaterThan
                    (probabilityOf "a" classifier [ 0, 0.8; 2, 0.6 ])
                    0.9
                    "confident for a's rows"

                Expect.isGreaterThan
                    (probabilityOf "b" classifier [ 1, 0.8; 2, 0.6 ])
                    0.9
                    "confident for b's rows"

            testCase "probabilities sum to one"
            <| fun () ->
                let classifier =
                    fitOrFail 3 (separable @ [ example [ 2, 1.0 ] "c" 1.0 ])

                let total =
                    LogisticRegression.probabilities
                        classifier
                        (vector [ 2, 1.0 ])
                    |> Array.sumBy snd

                Expect.floatClose Accuracy.veryHigh total 1.0 "a distribution"

            testCase "row weights change the fit"
            <| fun () ->
                // Both classes have the shared feature alone, a's rows at
                // three times the weight of b's.
                let examples weight = [
                    yield! List.replicate 5 (example [ 0, 1.0 ] "a" weight)
                    yield! List.replicate 5 (example [ 0, 1.0 ] "b" 1.0)
                ]

                let even = fitOrFail 1 (examples 1.0)
                let weighted = fitOrFail 1 (examples 3.0)

                Expect.floatClose
                    Accuracy.high
                    (probabilityOf "a" even [ 0, 1.0 ])
                    0.5
                    "equal weights are a tie"

                Expect.isGreaterThan
                    (probabilityOf "a" weighted [ 0, 1.0 ])
                    0.7
                    "the heavier class is more probable"

            testCase "a tie goes to the first class"
            <| fun () ->
                let classifier =
                    fitOrFail 1 [
                        example [ 0, 1.0 ] "b" 1.0
                        example [ 0, 1.0 ] "a" 1.0
                    ]

                Expect.equal
                    (LogisticRegression.predict classifier (vector [ 0, 1.0 ])
                     |> fst)
                    "a"
                    "classes are ordered by comparison"

            testCase "a single class is predicted with full confidence"
            <| fun () ->
                let classifier = fitOrFail 1 [ example [ 0, 1.0 ] "a" 1.0 ]

                Expect.equal
                    (LogisticRegression.predict classifier (vector []))
                    ("a", 1.0)
                    "the only class"

            testCase "no examples give no classifier"
            <| fun () ->
                Expect.isNone
                    (LogisticRegression.fit 1 ([] : Example<string> list))
                    "nothing to fit"

            testCase "the fit is deterministic"
            <| fun () ->
                let examples =
                    separable @ [ example [ 0, 0.5; 1, 0.5 ] "c" 2.0 ]

                let probabilities () =
                    LogisticRegression.probabilities
                        (fitOrFail 3 examples)
                        (vector [ 0, 0.3; 1, 0.4; 2, 0.5 ])

                Expect.equal
                    (probabilities ())
                    (probabilities ())
                    "the same examples give the same probabilities"
        ]
