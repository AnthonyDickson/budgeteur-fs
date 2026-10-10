namespace Budgeteur.Tests.IncomeStatement

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.IncomeStatement
    open Budgeteur.Feature.Transaction
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withTags
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withIncomeStatement
        )

    let private createTransaction
        (client : HttpClient)
        (date : DateOnly)
        (amount : decimal)
        (tagId : Guid option)
        (isTransfer : bool)
        =
        async {
            let request : CreateTransaction.CreateTransactionRequest = {
                Amount = amount
                Description = "Transaction"
                Date = date
                IsTransfer = isTransfer
                TagId = tagId
                AccountId = None
            }

            let! response =
                TestHttp.postJson client CreateTransaction.Path request |> Async.AwaitTask

            Expect.equal response.StatusCode HttpStatusCode.Created "creating a transaction should return 201"
        }

    let private october = "?from=2026-10-01&to=2026-10-31"

    let private getStatement (client : HttpClient) (query : string) =
        client.GetAsync (ReadIncomeStatement.Path + query) |> Async.AwaitTask

    let private expenseAmounts (lines : ExpenseLineResponse list) =
        lines |> List.map (fun line -> line.Name, line.Amount)

    // The arithmetic (refunds, ordering, shares) is covered by ComputeTests. These tests cover
    // what only the endpoint can get wrong: the query, the tag join, scoping, and the encoding.
    [<Tests>]
    let tests =
        testList "IncomeStatement" [
            testCaseAsync "the statement joins each transaction to its tag and kind"
            <| async {
                use app = newApp ()
                let day = DateOnly (2026, 10, 10)

                let! salary = Seed.tag app.Client "Salary" "Income"
                let! rent = Seed.tag app.Client "Rent" "Expense"

                do! createTransaction app.Client day 5000m (Some salary) false
                do! createTransaction app.Client day -2000m (Some rent) false
                do! createTransaction app.Client day -25m None false

                let! response = getStatement app.Client october
                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
                Expect.stringContains body "\"netIncome\":\"2975" "money should be serialised as a JSON string"

                let! statement = TestHttp.readJson<IncomeStatementResponse> response

                Expect.equal statement.From (DateOnly (2026, 10, 1)) "from should echo the period"
                Expect.equal statement.To (DateOnly (2026, 10, 31)) "to should echo the period"

                Expect.equal
                    (statement.IncomeLines
                     |> List.map (fun line -> line.TagId, line.Name, line.Amount))
                    [ Some salary, "Salary", 5000m ]
                    "the income tag's transaction should be income"

                Expect.equal
                    (statement.ExpenseLines
                     |> List.map (fun line -> line.TagId, line.Name, line.Amount))
                    [ Some rent, "Rent", 2000m; None, "Untagged expenses", 25m ]
                    "the expense tag's and the untagged transactions should be expenses"

                Expect.equal statement.UntaggedCount 1 "the untagged transaction should be counted"
            }

            testCaseAsync "transfers and transactions outside the period are excluded"
            <| async {
                use app = newApp ()
                let! rent = Seed.tag app.Client "Rent" "Expense"

                do! createTransaction app.Client (DateOnly (2026, 10, 1)) -100m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 10, 31)) -10m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 10, 15)) -999m (Some rent) true
                do! createTransaction app.Client (DateOnly (2026, 10, 15)) 999m None true
                do! createTransaction app.Client (DateOnly (2026, 9, 30)) -1000m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 11, 1)) -1000m (Some rent) false

                let! response = getStatement app.Client october
                let! statement = TestHttp.readJson<IncomeStatementResponse> response

                Expect.equal statement.Expenses 110m "only the first and last day of the period should count"
                Expect.equal statement.Income 0m "the transfer in should not count as income"
                Expect.equal statement.UntaggedCount 0 "an untagged transfer should not be counted"
            }

            testCaseAsync "the statement is scoped to the user"
            <| async {
                use app = newApp ()
                let other = app.ClientForUser "other-user"
                let day = DateOnly (2026, 10, 10)

                let! otherRent = Seed.tag other "Rent" "Expense"
                do! createTransaction other day -2000m (Some otherRent) false
                do! createTransaction app.Client day -25m None false

                let! response = getStatement app.Client october
                let! statement = TestHttp.readJson<IncomeStatementResponse> response

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ "Untagged expenses", 25m ]
                    "another user's transactions should not be included"
            }

            testCaseAsync "an invalid period is reported as a bad request"
            <| async {
                use app = newApp ()

                let! response = getStatement app.Client ""

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "a missing period should be rejected"
            }
        ]
