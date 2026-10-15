namespace Budgeteur.Tests

module PatternMatchTests =
    open System
    open Expecto
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db

    let private userId = "test-user"

    /// <summary>Store transactions with the descriptions and return the
    /// descriptions the pattern matches, through a query that calls the
    /// function in its <c>where</c> clause.</summary>
    let private matchesIn (descriptions : string list) (pattern : string) =
        task {
            use app = TestApp.create TestAppConfig.empty
            let queryContext = QueryContextFactory.Create app.ConnectionString
            use! ctx = queryContext.OpenContextAsync ()
            PatternMatch.register ctx

            for description in descriptions do
                let row : main.Transactions = {
                    Id = Guid.CreateVersion7 ()
                    UserId = userId
                    Amount = -1m
                    Description = description
                    Date = DateOnly (2026, 3, 8)
                    AccountId = None
                    ImportHash = None
                }

                let! _ =
                    insertTask ctx {
                        for t in main.Transactions do
                            entity row
                    }

                ()

            let! matched =
                selectTask ctx {
                    for t in main.Transactions do
                        where (
                            t.UserId = userId
                            && PatternMatch.position (t.Description, pattern) >
                                0
                        )

                        select t.Description
                }

            return matched |> List.ofSeq |> List.sort
        }

    [<Tests>]
    let tests =
        testList "PatternMatch" [
            testTask "ignores ASCII case" {
                let! matched =
                    matchesIn [ "COUNTDOWN AUCKLAND"; "NEW WORLD" ] "countdown"

                Expect.equal matched [ "COUNTDOWN AUCKLAND" ] "matched"
            }

            testTask "ignores non-ASCII case" {
                let! matched = matchesIn [ "ŌTAKI FUEL"; "OTAKI FUEL" ] "ōtaki"
                Expect.equal matched [ "ŌTAKI FUEL" ] "matched"
            }

            testTask "treats % as a plain character" {
                let! matched = matchesIn [ "50% OFF"; "500 OFF" ] "50%"
                Expect.equal matched [ "50% OFF" ] "matched"
            }

            testTask "treats _ as a plain character" {
                let! matched = matchesIn [ "A_B"; "AXB" ] "a_b"
                Expect.equal matched [ "A_B" ] "matched"
            }
        ]
