namespace Budgeteur.Tests

open Expecto

open Budgeteur.Shared.Money

/// <summary>
/// Property-based tests for <c>Budgeteur.Shared.Money.create</c>, the only way to build a
/// <c>Money</c> from untrusted input. The Update endpoint once used F# core <c>round</c>
/// (nearest integer) instead, silently corrupting amounts; these properties pin the rounding
/// contract so it can never regress silently.
/// </summary>
module MoneyTests =
    let private cents (amount : decimal) = Money.value (Money.create amount)

    /// Created values are always exact cents (multiples of 0.01).
    let private propIsCents (amount : decimal) = cents amount * 100m % 1m = 0m

    /// Creating from an already created value changes nothing.
    let private propIdempotent (amount : decimal) = cents (cents amount) = cents amount

    /// Rounding never moves the value by more than half a cent.
    let private propWithinHalfCent (amount : decimal) = abs (cents amount - amount) <= 0.005m

    [<Tests>]
    let moneyTests =
        testList "Money" [
            testProperty "create always yields exact cents" propIsCents
            testProperty "create is idempotent" propIdempotent
            testProperty "create moves values by at most half a cent" propWithinHalfCent

            testCase "create rounds half away from zero (positive)"
            <| fun () -> Expect.equal (cents 13.375m) 13.38m "13.375 rounds up"

            testCase "create rounds half away from zero (negative)"
            <| fun () -> Expect.equal (cents -13.375m) -13.38m "-13.375 rounds away from zero"

            testCase "create keeps 2 dp values unchanged"
            <| fun () -> Expect.equal (cents 12.50m) 12.50m "12.50 is already cents"
        ]
