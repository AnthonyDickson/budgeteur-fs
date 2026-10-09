namespace Budgeteur.Tests.IncomeStatement

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.IncomeStatement
    open Budgeteur.Feature.Tag
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withTags
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withIncomeStatement
        )

    let private decodeBody<'T> (response : HttpResponseMessage) : Async<'T> =
        async {
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

            match Decode.fromStringAuto<'T> body with
            | Ok value -> return value
            | Error error -> return failtest error
        }

    /// Create a tag and return its server-assigned id.
    let private createTag (client : HttpClient) (name : string) (kind : string) : Async<Guid> =
        async {
            let request : CreateTag.CreateTagRequest = {
                Name = name
                Color = "#6366F1"
                Kind = kind
            }

            let! response = TestHttp.postJson client CreateTag.Path request |> Async.AwaitTask
            Expect.equal response.StatusCode HttpStatusCode.Created "creating a tag should return 201"
            let! tag = decodeBody<TagResponse> response
            return tag.Id
        }

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

    let private lineAmounts (lines : IncomeLineResponse list) =
        lines |> List.map (fun line -> line.Name, line.Amount)

    let private expenseAmounts (lines : ExpenseLineResponse list) =
        lines |> List.map (fun line -> line.Name, line.Amount)

    [<Tests>]
    let tests =
        testList "IncomeStatement" [
            testCaseAsync "the statement totals the period's transactions by tag kind"
            <| async {
                use app = newApp ()
                let day = DateOnly (2026, 10, 10)

                let! salary = createTag app.Client "Salary" "Income"
                let! rent = createTag app.Client "Rent" "Expense"
                let! groceries = createTag app.Client "Groceries" "Expense"

                do! createTransaction app.Client day 5000m (Some salary) false
                do! createTransaction app.Client day -2000m (Some rent) false
                do! createTransaction app.Client day -300m (Some groceries) false
                do! createTransaction app.Client day 50m (Some groceries) false
                do! createTransaction app.Client day -25m None false

                let! response = getStatement app.Client october
                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
                Expect.stringContains body "\"netIncome\":\"2725" "money should be serialised as a JSON string"

                let statement =
                    match Decode.fromStringAuto<IncomeStatementResponse> body with
                    | Ok statement -> statement
                    | Error error -> failtest error

                Expect.equal statement.From (DateOnly (2026, 10, 1)) "from should echo the period"
                Expect.equal statement.To (DateOnly (2026, 10, 31)) "to should echo the period"
                Expect.equal statement.Income 5000m "income should be the salary"
                Expect.equal statement.Expenses 2275m "expenses should be net of the refund"
                Expect.equal statement.NetIncome 2725m "net income should be income minus expenses"
                Expect.equal (lineAmounts statement.IncomeLines) [ "Salary", 5000m ] "income lines"

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ "Rent", 2000m; "Groceries", 250m; "Untagged expenses", 25m ]
                    "expense lines"

                Expect.equal
                    (statement.ExpenseLines |> List.map (fun line -> line.TagId))
                    [ Some rent; Some groceries; None ]
                    "tagged lines should carry the tag id and the untagged line none"

                Expect.equal statement.UntaggedCount 1 "the untagged transaction should be counted"
            }

            testCaseAsync "transfers and transactions outside the period are excluded"
            <| async {
                use app = newApp ()
                let! rent = createTag app.Client "Rent" "Expense"

                do! createTransaction app.Client (DateOnly (2026, 10, 1)) -100m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 10, 31)) -10m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 10, 15)) -999m (Some rent) true
                do! createTransaction app.Client (DateOnly (2026, 10, 15)) 999m None true
                do! createTransaction app.Client (DateOnly (2026, 9, 30)) -1000m (Some rent) false
                do! createTransaction app.Client (DateOnly (2026, 11, 1)) -1000m (Some rent) false

                let! response = getStatement app.Client october
                let! statement = decodeBody<IncomeStatementResponse> response

                Expect.equal statement.Expenses 110m "only the first and last day of the period should count"
                Expect.equal statement.Income 0m "the transfer in should not count as income"
                Expect.equal statement.UntaggedCount 0 "an untagged transfer should not be counted"
            }

            testCaseAsync "the statement is scoped to the user"
            <| async {
                use app = newApp ()
                let other = app.ClientForUser "other-user"
                let day = DateOnly (2026, 10, 10)

                let! otherRent = createTag other "Rent" "Expense"
                do! createTransaction other day -2000m (Some otherRent) false
                do! createTransaction app.Client day -25m None false

                let! response = getStatement app.Client october
                let! statement = decodeBody<IncomeStatementResponse> response

                Expect.equal
                    (expenseAmounts statement.ExpenseLines)
                    [ "Untagged expenses", 25m ]
                    "another user's transactions should not be included"
            }

            testCaseAsync "an invalid period is reported as a bad request"
            <| async {
                use app = newApp ()

                let expectBadRequest (query : string) (expected : string list) =
                    async {
                        let! response = getStatement app.Client query

                        Expect.equal
                            response.StatusCode
                            HttpStatusCode.BadRequest
                            $"'{query}' should be rejected with a 400"

                        let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                        for text in expected do
                            Expect.stringContains body text $"the error for '{query}' should mention {text}"
                    }

                do! expectBadRequest "" [ "'from'"; "'to'" ]
                do! expectBadRequest "?from=2026-10-01&to=31/10/2026" [ "'to'" ]
                do! expectBadRequest "?from=2026-10-31&to=2026-10-01" [ "must not be after" ]
                do! expectBadRequest "?from=2026-01-01&to=2027-01-02" [ "at most 366 days" ]
            }
        ]
