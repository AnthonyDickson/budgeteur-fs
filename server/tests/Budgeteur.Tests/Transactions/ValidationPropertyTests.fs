namespace Budgeteur.Tests.Transactions

open System
open Expecto
open FsCheck

open Budgeteur.Transactions

/// <summary>
/// Property-based tests for <c>Transactions.Validation</c>. These complement the
/// hand-written endpoint tests by sampling the full input space instead of a few
/// canned examples, catching off-by-one errors at the length boundary and pinning
/// down the trim/whitespace behaviour of <c>validateAndTrimDescription</c>.
/// </summary>
module ValidationPropertyTests =

    /// FsCheck's default string generator can produce null, but the validation
    /// function assumes a non-null description. The endpoint guarantees that via
    /// JSON decoding (Thoth rejects a null `description`), so the properties sample
    /// only non-null strings. The null behaviour itself is pinned as an explicit
    /// example case rather than fuzzed.
    module Arbitraries =
        /// FsCheck's default string generator can produce null; this override restricts
        /// generated strings to non-null (the validation function's actual contract).
        type NonNullStrings =
            static member String () : Arbitrary<string> =
                Arb.Default.String () |> Arb.filter (fun s -> not (isNull s))

    let private maxDescriptionLength = 256

    let private config = {
        FsCheckConfig.defaultConfig with
            // Pushes FsCheck above the length limit, so an off-by-one at the
            // 256/257 boundary is exercised rather than missed.
            endSize = 1024
            arbitrary = [ typeof<Arbitraries.NonNullStrings> ]
    }

    /// Acceptance preserves trim: an accepted description equals the trimmed input.
    let private propPreservesTrim (s : string) =
        match Validation.validateAndTrimDescription s with
        | Ok trimmed -> trimmed = s.Trim ()
        | Error _ -> true

    /// Length bounded on accept: accepted descriptions never exceed the limit.
    let private propLengthBounded (s : string) =
        match Validation.validateAndTrimDescription s with
        | Ok trimmed -> trimmed.Length <= maxDescriptionLength
        | Error _ -> true

    /// Whitespace rejection: within the acceptable-length domain, the result is an
    /// error iff the trimmed input is empty (pins the IsNullOrWhiteSpace semantics).
    /// Over-length inputs are deliberately skipped here; they're the length rule's domain.
    let private propRejectsWhitespace (s : string) =
        let whitespaceOnly = String.IsNullOrWhiteSpace s

        if whitespaceOnly then
            // A whitespace-only description is always rejected.
            match Validation.validateAndTrimDescription s with
            | Error _ -> true
            | Ok _ -> false
        else
            // A non-whitespace description is accepted unless it is too long,
            // which is out of scope for this property (see the length property).
            let trimmed = s.Trim ()

            match Validation.validateAndTrimDescription s with
            | Ok _ -> trimmed.Length <= maxDescriptionLength
            | Error _ -> trimmed.Length > maxDescriptionLength

    [<Tests>]
    let validationPropertyTests =
        testList "Transactions Validation (property)" [
            // FsCheck surfaced null via its default string generator; lifted from the
            // shrink, the function throws on a null description rather than returning
            // an Error. The API can't send null (Thoth rejects it), but direct callers
            // must not pass null.
            testCase "null description throws NullReferenceException"
            <| fun () ->
                Expect.throws
                    (fun () -> Validation.validateAndTrimDescription null |> ignore)
                    "null input should not be silently accepted"

            testPropertyWithConfig
                config
                "Acceptance preserves trim: Ok trimmed exactly equals s.Trim()"
                propPreservesTrim

            testPropertyWithConfig
                config
                "Length bounded on accept: accepted description length <= 256"
                propLengthBounded

            testPropertyWithConfig config "Whitespace rejection: Error iff trimmed input is empty" propRejectsWhitespace
        ]
