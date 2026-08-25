namespace Budgeteur.Tests

open System
open Expecto
open FsCheck

open Budgeteur.Shared.Money

/// <summary>
/// Property-based tests for <c>Budgeteur.Shared.Money.roundToCents</c>. The Update
/// endpoint once used F# core <c>round</c> (nearest integer) instead, silently
/// corrupting amounts; these properties pin the contract of the single shared
/// rounding function so the behaviour can never regress silently.
/// </summary>
module MoneyTests =

    /// Rounded values are always exact cents (multiples of 0.01).
    let private propIsCents (amount : decimal) =
        let rounded = Money.roundToCents amount
        rounded * 100m % 1m = 0m

    /// Rounding is idempotent.
    let private propIdempotent (amount : decimal) =
        Money.roundToCents (Money.roundToCents amount) = Money.roundToCents amount

    /// Rounding never moves the value by more than half a cent.
    let private propWithinHalfCent (amount : decimal) =
        let rounded = Money.roundToCents amount
        abs (rounded - amount) <= 0.005m

    [<Tests>]
    let moneyTests =
        testList "Money" [
            testProperty "roundToCents always yields exact cents" propIsCents
            testProperty "roundToCents is idempotent" propIdempotent
            testProperty "roundToCents moves values by at most half a cent" propWithinHalfCent

            testCase "roundToCents rounds half away from zero (positive)"
            <| fun () -> Expect.equal (Money.roundToCents 13.375m) 13.38m "13.375 rounds up"

            testCase "roundToCents rounds half away from zero (negative)"
            <| fun () -> Expect.equal (Money.roundToCents -13.375m) -13.38m "-13.375 rounds away from zero"

            testCase "roundToCents keeps 2 dp values unchanged"
            <| fun () -> Expect.equal (Money.roundToCents 12.50m) 12.50m "12.50 is already cents"
        ]
