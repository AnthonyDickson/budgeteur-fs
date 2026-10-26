namespace Budgeteur.Domain.Lbfgs

open System
open System.Numerics.Tensors

/// <summary>A function to minimise: it writes the gradient at the point (the
/// first array) into the second array, and returns the value at the
/// point.</summary>
type Objective = float array -> float array -> float

/// <summary>Where a minimisation stopped.</summary>
type Minimum = {
    Point : float array
    Value : float
    Iterations : int
    /// <summary>Whether the gradient met the tolerance, rather than the
    /// iteration cap or a failed line search stopping the
    /// minimisation.</summary>
    Converged : bool
}

/// <summary>An evaluated step along the search direction.</summary>
type private Trial = {
    Step : float
    Value : float
    /// <summary>The directional derivative at the step.</summary>
    Slope : float
}

/// <summary>Limited-memory BFGS with a strong Wolfe line search, as Nocedal and
/// Wright give them in <i>Numerical Optimization</i> (2nd edition, algorithms
/// 7.4, 7.5, 3.5, and 3.6). See decision 2 in docs/smart-tagging.md.</summary>
/// <remarks>A minimisation allocates its vectors once and updates them in
/// place: the vectors are long enough to be large objects, which are costly to
/// allocate and collect. <c>minimise</c> is still pure.</remarks>
module Lbfgs =
    /// <summary>The sufficient decrease constant of the Wolfe
    /// conditions.</summary>
    let private c1 = 1e-4

    /// <summary>The curvature constant of the Wolfe conditions, the usual
    /// choice for quasi-Newton methods.</summary>
    let private c2 = 0.9

    /// <summary>The most evaluations one line search makes.</summary>
    let private maxTrials = 40

    let private dot (a : float array) (b : float array) =
        TensorPrimitives.Dot (ReadOnlySpan a, ReadOnlySpan b)

    /// <summary><c>target += scale * source</c>.</summary>
    let private addScaled
        (target : float array)
        (scale : float)
        (source : float array)
        =
        TensorPrimitives.MultiplyAdd (
            ReadOnlySpan source,
            scale,
            ReadOnlySpan target,
            Span target
        )

    /// <summary><c>target = scale * source</c>.</summary>
    let private scaled
        (target : float array)
        (scale : float)
        (source : float array)
        =
        TensorPrimitives.Multiply (ReadOnlySpan source, scale, Span target)

    /// <summary><c>target = a + scale * b</c>.</summary>
    let private sumScaled
        (target : float array)
        (a : float array)
        (scale : float)
        (b : float array)
        =
        TensorPrimitives.MultiplyAdd (
            ReadOnlySpan b,
            scale,
            ReadOnlySpan a,
            Span target
        )

    /// <summary>The largest magnitude of the vector's components.</summary>
    let private largest (vector : float array) =
        abs (TensorPrimitives.MaxMagnitude (ReadOnlySpan vector))

    /// <summary>The minimiser of the cubic through two trials' values and
    /// slopes, kept away from the ends of the interval between them, or the
    /// midpoint when the cubic has no minimiser there.</summary>
    let private interpolate (lo : Trial) (hi : Trial) =
        let d1 =
            lo.Slope + hi.Slope
            - 3.0 * (lo.Value - hi.Value) / (lo.Step - hi.Step)

        let discriminant = d1 * d1 - lo.Slope * hi.Slope
        let midpoint = (lo.Step + hi.Step) / 2.0

        if discriminant < 0.0 then
            midpoint
        else
            let d2 = float (sign (hi.Step - lo.Step)) * sqrt discriminant

            let step =
                hi.Step
                - (hi.Step - lo.Step) * (hi.Slope + d2 - d1)
                  / (hi.Slope - lo.Slope + 2.0 * d2)

            let low, high = min lo.Step hi.Step, max lo.Step hi.Step
            let margin = 0.1 * (high - low)

            if
                Double.IsFinite step
                && step > low + margin
                && step < high - margin
            then
                step
            else
                midpoint

    /// <summary>A step meeting the strong Wolfe conditions, searched from a
    /// step of 1, or None when none is found within the trial limit. It first
    /// brackets a step, doubling until one fails, then narrows the bracket.
    /// <c>evaluate</c> evaluates a step, leaving its point and gradient where
    /// the caller reads them, and an accepted step is always the last
    /// evaluated.</summary>
    let private lineSearch
        (evaluate : float -> Trial)
        (start : Trial)
        : Trial option =
        let sufficient (trial : Trial) =
            trial.Value <= start.Value + c1 * trial.Step * start.Slope

        let curved (trial : Trial) = abs trial.Slope <= -c2 * start.Slope

        let mutable accepted = None
        let mutable trials = 0
        let mutable bracketed = false
        let mutable step = 1.0
        // While bracketing, `lo` is the previous trial; once bracketed, the
        // acceptable step lies between `lo`, the lower value, and `hi`.
        let mutable lo = start
        let mutable hi = start

        while Option.isNone accepted && trials < maxTrials do
            if not bracketed then
                let trial = evaluate step

                if
                    not (sufficient trial)
                    || (trials > 0 && trial.Value >= lo.Value)
                then
                    hi <- trial
                    bracketed <- true
                elif curved trial then
                    accepted <- Some trial
                elif trial.Slope >= 0.0 then
                    hi <- lo
                    lo <- trial
                    bracketed <- true
                else
                    lo <- trial
                    step <- 2.0 * step
            else
                let trial = evaluate (interpolate lo hi)

                if not (sufficient trial) || trial.Value >= lo.Value then
                    hi <- trial
                elif curved trial then
                    accepted <- Some trial
                else
                    if trial.Slope * (hi.Step - lo.Step) >= 0.0 then
                        hi <- lo

                    lo <- trial

            trials <- trials + 1

        accepted

    /// <summary>Minimise the objective from the start. Stops when every
    /// gradient component is within the tolerance, after the iteration cap, or
    /// when a line search fails, such as when the remaining decrease is below
    /// rounding error. The same objective and start always give the same
    /// minimum.</summary>
    let minimise
        (tolerance : float)
        (memory : int)
        (maxIterations : int)
        (objective : Objective)
        (start : float array)
        : Minimum =
        let size = start.Length
        let point = Array.copy start
        let gradient = Array.zeroCreate size
        let mutable value = objective point gradient
        let trialPoint = Array.zeroCreate size
        let trialGradient = Array.zeroCreate size
        let direction = Array.zeroCreate size

        // The history of (s, y, 1 / (y · s)) pairs, a ring buffer whose
        // newest pair is at `newest`.
        let s = Array.init memory (fun _ -> Array.zeroCreate size)
        let y = Array.init memory (fun _ -> Array.zeroCreate size)
        let rho = Array.zeroCreate memory
        let alpha = Array.zeroCreate memory
        let stored = ref 0
        let newest = ref 0
        let pair age = (newest.Value - age + memory) % memory
        // The newest pair's (s · y) / (y · y), which scales the initial
        // inverse Hessian approximation.
        let scaling = ref 1.0

        /// The two-loop recursion: minus the inverse Hessian approximation
        /// times the gradient.
        let searchDirection () =
            scaled direction -1.0 gradient

            for age in 0 .. stored.Value - 1 do
                let i = pair age
                alpha[i] <- rho[i] * dot s[i] direction

                addScaled direction -alpha[i] y[i]

            // Without history the direction is the unit steepest descent, so
            // every line search can start from a step of 1.
            let gamma =
                if stored.Value > 0 then
                    scaling.Value
                else
                    1.0 / sqrt (dot gradient gradient)

            scaled direction gamma direction

            for age in stored.Value - 1 .. -1 .. 0 do
                let i = pair age
                let beta = rho[i] * dot y[i] direction

                addScaled direction (alpha[i] - beta) s[i]

        let evaluate step =
            sumScaled trialPoint point step direction

            let value = objective trialPoint trialGradient

            {
                Step = step
                Value = value
                Slope = dot trialGradient direction
            }

        let mutable iterations = 0
        let mutable stopped = false

        while not stopped
              && largest gradient > tolerance
              && iterations < maxIterations do
            searchDirection ()

            // Rounding can make the direction uphill; the gradient always is
            // downhill.
            if dot gradient direction >= 0.0 then
                stored.Value <- 0
                searchDirection ()

            let slope = dot gradient direction

            match
                lineSearch evaluate {
                    Step = 0.0
                    Value = value
                    Slope = slope
                }
            with
            | None -> stopped <- true
            | Some trial ->
                let next = (newest.Value + 1) % memory

                sumScaled s[next] trialPoint -1.0 point
                sumScaled y[next] trialGradient -1.0 gradient

                // The strong Wolfe conditions make the curvature positive;
                // rounding aside.
                let sy = dot s[next] y[next]

                if sy > 0.0 then
                    rho[next] <- 1.0 / sy
                    scaling.Value <- sy / dot y[next] y[next]
                    newest.Value <- next
                    stored.Value <- min memory (stored.Value + 1)

                Array.blit trialPoint 0 point 0 size
                Array.blit trialGradient 0 gradient 0 size
                value <- trial.Value
                iterations <- iterations + 1

        {
            Point = point
            Value = value
            Iterations = iterations
            Converged = largest gradient <= tolerance
        }
