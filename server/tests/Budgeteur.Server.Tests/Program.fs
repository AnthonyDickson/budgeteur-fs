module Budgeteur.Server.Tests.Program

open Expecto
open Budgeteur.Server.Tests

/// <summary>
/// Composes every test list into a single, explicitly-named root. We avoid the
/// assembly-level reflection runner (`runTestsInAssemblyWithCLIArgs`) because it
/// reports an anonymous `miscellaneous` root and hides new suites until they are
/// wired up here.
/// </summary>
let testRoot =
    testList "Budgeteur.Server.Tests" [
        Transactions.EndpointTests.tests
        Transactions.ValidationPropertyTests.validationPropertyTests
    ]

[<EntryPoint>]
let main args = runTestsWithCLIArgs [] args testRoot
