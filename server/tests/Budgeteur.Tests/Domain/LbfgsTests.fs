namespace Budgeteur.Tests

open Expecto

open Budgeteur.Domain.Lbfgs

module LbfgsTests =
    /// Rosenbrock's function, curved and badly scaled, with its minimum of 0
    /// at (1, 1).
    let private rosenbrock (point : float array) =
        let x, y = point[0], point[1]

        (1.0 - x) ** 2.0 + 100.0 * (y - x * x) ** 2.0,
        [| -2.0 * (1.0 - x) - 400.0 * x * (y - x * x); 200.0 * (y - x * x) |]

    /// The usual start for Rosenbrock's function.
    let private rosenbrockStart = [| -1.2; 1.0 |]

    /// A quadratic with curvatures from 1 to 8,000: the sum of (i + 1) cubed
    /// times the square of component i, with its minimum of 0 at the origin.
    let private quadratic (point : float array) =
        let scale i = float (i + 1) ** 3.0

        point |> Array.mapi (fun i x -> scale i * x * x) |> Array.sum,
        point |> Array.mapi (fun i x -> 2.0 * scale i * x)

    /// The objective of a function giving the value and gradient.
    let private objectiveOf
        (f : float array -> float * float array)
        : Objective =
        fun point gradient ->
            let value, found = f point
            Array.blit found 0 gradient 0 found.Length
            value

    [<Tests>]
    let tests =
        testList "Lbfgs" [
            testCase "minimises Rosenbrock's function"
            <| fun () ->
                let minimum =
                    Lbfgs.minimise
                        1e-8
                        10
                        1000
                        (objectiveOf rosenbrock)
                        rosenbrockStart

                Expect.isTrue minimum.Converged "converged"
                Expect.floatClose Accuracy.medium minimum.Point[0] 1.0 "x"
                Expect.floatClose Accuracy.medium minimum.Point[1] 1.0 "y"

            testCase "minimises an ill-conditioned quadratic"
            <| fun () ->
                let minimum =
                    Lbfgs.minimise
                        1e-8
                        5
                        1000
                        (objectiveOf quadratic)
                        (Array.create 20 1.0)

                Expect.isTrue minimum.Converged "converged"

                // A gradient within 1e-8 puts component i within
                // 1e-8 / (2 (i + 1)^3) of the origin.
                minimum.Point
                |> Array.iteri (fun i x ->
                    Expect.isLessThanOrEqual
                        (abs x)
                        (1e-8 / (2.0 * float (i + 1) ** 3.0))
                        $"component %i{i} at the origin")

            testCase "a start at the minimum stops at once"
            <| fun () ->
                let minimum =
                    Lbfgs.minimise
                        1e-8
                        10
                        1000
                        (objectiveOf quadratic)
                        (Array.zeroCreate 2)

                Expect.equal
                    (minimum.Iterations, minimum.Converged)
                    (0, true)
                    "no iterations"

            testCase "the iteration cap stops an unconverged minimisation"
            <| fun () ->
                let minimum =
                    Lbfgs.minimise
                        1e-12
                        10
                        3
                        (objectiveOf rosenbrock)
                        rosenbrockStart

                Expect.equal
                    (minimum.Iterations, minimum.Converged)
                    (3, false)
                    "stopped at the cap"

            testCase "the same start gives the same minimum"
            <| fun () ->
                let minimise () =
                    Lbfgs.minimise
                        1e-8
                        10
                        1000
                        (objectiveOf rosenbrock)
                        rosenbrockStart

                Expect.equal (minimise ()) (minimise ()) "deterministic"
        ]
