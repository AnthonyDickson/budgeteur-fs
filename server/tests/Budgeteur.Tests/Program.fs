module Budgeteur.Tests.Program

open Expecto
open Budgeteur.Tests

/// <summary>
/// Composes every test list into a single, explicitly-named root. We avoid the
/// assembly-level reflection runner (`runTestsInAssemblyWithCLIArgs`) because it
/// reports an anonymous `miscellaneous` root and hides new suites until they are
/// wired up here.
/// </summary>
let testRoot =
    testList "Budgeteur.Tests" [
        Transactions.EndpointTests.tests
        Transactions.ValidationPropertyTests.validationPropertyTests
        MoneyTests.moneyTests
    ]

[<EntryPoint>]
let main args = runTestsWithCLIArgs [] args testRoot
