namespace Budgeteur.Tests.Dashboard

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Feature.Dashboard
    open Budgeteur.Feature.QuickTag
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    /// The server's clock: 14 October 2026, after every date the tests use.
    let private clock : Clock =
        fun () -> DateTimeOffset (2026, 10, 14, 0, 0, 0, TimeSpan.Zero)

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withBalanceSheet clock
            |> TestAppConfig.withTags
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withQuickTag
            |> TestAppConfig.withDashboard
        )

    let private getDashboard (client : HttpClient) (query : string) =
        client.GetAsync (ReadDashboard.Path + query) |> Async.AwaitTask

    let private onToday = "?today=2026-10-14"

    let private postTransaction
        (client : HttpClient)
        (date : DateOnly)
        (amount : decimal)
        (tagId : Guid option)
        (isTransfer : bool)
        =
        async {
            let! response =
                TestHttp.postJson
                    client
                    CreateTransaction.Path
                    ({
                        Amount = amount
                        Description = "Transaction"
                        Date = date
                        IsTransfer = isTransfer
                        TagId = tagId
                        AccountId = None
                    }
                    : CreateTransaction.CreateTransactionRequest)
                |> Async.AwaitTask

            return! TestHttp.readJson<TransactionResponse> response
        }

    let private createTransaction
        (client : HttpClient)
        (date : DateOnly)
        (amount : decimal)
        =
        postTransaction client date amount None false |> Async.Ignore

    let private readDashboard (client : HttpClient) =
        async {
            let! response = getDashboard client onToday
            return! TestHttp.readJson<DashboardResponse> response
        }

    let private lineAmounts (lines : MonthLineResponse list) =
        lines |> List.map (fun line -> line.Name, line.Amount)

    // The figures are covered by the periods, month, and history tests. These
    // tests cover what only the endpoint can get wrong: the query, loading,
    // scoping, and encoding.
    [<Tests>]
    let tests =
        testList "Dashboard endpoint" [
            testCaseAsync "the dashboard is read from the user's data"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! _ =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        ({
                            Name = "House"
                            Side = "Asset"
                            Term = "NonCurrent"
                            Value = 400000m
                            AsOf = DateOnly (2026, 8, 10)
                        }
                        : CreateBalanceSheetItemRequest)
                    |> Async.AwaitTask

                do! createTransaction app.Client (DateOnly (2026, 9, 1)) -1000m
                do! createTransaction app.Client (DateOnly (2026, 10, 5)) -400m

                // When: the dashboard is read on 14 October.
                let! response = getDashboard app.Client onToday
                Expect.equal response.StatusCode HttpStatusCode.OK "200"

                let! body =
                    response.Content.ReadAsStringAsync () |> Async.AwaitTask

                let! dashboard = TestHttp.readJson<DashboardResponse> response

                // Then: the month is compared with September's same days.
                Expect.equal dashboard.Month.Label "October 2026" "the month"

                Expect.equal
                    dashboard.Month.Expenses
                    {
                        Amount = 400m
                        Baseline = Some 1000m
                        Change = Some -600m
                        ChangePercent = Some -60m
                    }
                    "October's expenses against September's"

                Expect.equal
                    dashboard.Month.LatestTransaction
                    (Some (DateOnly (2026, 10, 5)))
                    "the latest transaction"

                // Then: the history starts at the house's value in August.
                Expect.equal
                    (dashboard.History |> List.map _.Label)
                    [ "August 2026"; "September 2026"; "October 2026" ]
                    "the history months"

                Expect.equal
                    (dashboard.Totals |> Option.map _.AverageExpenses)
                    (Some 1000m)
                    "September is the only baseline month"

                Expect.equal dashboard.Position.NetWorth 400000m "the house"

                Expect.equal
                    dashboard.Position.OldestAsOf
                    (Some (DateOnly (2026, 8, 10)))
                    "the house's as-of date"

                Expect.stringContains
                    body
                    "\"netWorth\":\"400000"
                    "money is serialised as a string"

                // Then: another user has none of it.
                let! foreign = getDashboard otherUser onToday
                let! foreign = TestHttp.readJson<DashboardResponse> foreign

                Expect.isTrue foreign.Position.IsEmpty "no balance sheet"
                Expect.isEmpty foreign.Month.ExpenseLines "no transactions"
                Expect.isNone foreign.Totals "no baseline months"

                Expect.equal
                    (foreign.History |> List.map _.Label)
                    [ "October 2026" ]
                    "today's month only"
            }

            testCaseAsync "each transaction is joined to its tag and kind"
            <| async {
                use app = newApp ()
                let day = DateOnly (2026, 10, 10)

                let! salary = Seed.tag app.Client "Salary" "Income"
                let! rent = Seed.tag app.Client "Rent" "Expense"

                do!
                    postTransaction app.Client day 5000m (Some salary) false
                    |> Async.Ignore

                do!
                    postTransaction app.Client day -2000m (Some rent) false
                    |> Async.Ignore

                do! createTransaction app.Client day -25m

                let! dashboard = readDashboard app.Client

                Expect.equal
                    (dashboard.Month.IncomeLines
                     |> List.map (fun line ->
                         line.TagId, line.Name, line.Amount))
                    [ Some salary, "Salary", 5000m ]
                    "the income tag's transaction is income"

                Expect.equal
                    (dashboard.Month.ExpenseLines
                     |> List.map (fun line ->
                         line.TagId, line.Name, line.Amount))
                    [ Some rent, "Rent", 2000m; None, "Untagged expenses", 25m ]
                    "the expense tag's and the untagged transactions are \
                    expenses"
            }

            testCaseAsync "a dismissed transaction counts as untagged"
            <| async {
                use app = newApp ()

                let! created =
                    postTransaction
                        app.Client
                        (DateOnly (2026, 10, 10))
                        -25m
                        None
                        false

                let! response =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath DismissTransaction.Path created.Id
                    )
                    |> Async.AwaitTask

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.NoContent
                    "dismissing returns 204"

                let! dashboard = readDashboard app.Client

                Expect.equal
                    (lineAmounts dashboard.Month.ExpenseLines)
                    [ "Untagged expenses", 25m ]
                    "a dismissal has no tag, so it is an untagged expense"
            }

            testCaseAsync "transfers and transactions after today are excluded"
            <| async {
                use app = newApp ()

                do! createTransaction app.Client (DateOnly (2026, 10, 1)) -100m
                do! createTransaction app.Client (DateOnly (2026, 10, 14)) -10m

                do!
                    postTransaction
                        app.Client
                        (DateOnly (2026, 10, 5))
                        -999m
                        None
                        true
                    |> Async.Ignore

                do!
                    postTransaction
                        app.Client
                        (DateOnly (2026, 10, 5))
                        999m
                        None
                        true
                    |> Async.Ignore

                do!
                    createTransaction
                        app.Client
                        (DateOnly (2026, 10, 15))
                        -1000m

                let! dashboard = readDashboard app.Client

                Expect.equal
                    dashboard.Month.Expenses.Amount
                    110m
                    "the first of the month and today count"

                Expect.equal
                    dashboard.Month.Income.Amount
                    0m
                    "the transfer in is not income"
            }

            testCaseAsync "a missing or malformed today is rejected"
            <| async {
                use app = newApp ()

                let! missing = getDashboard app.Client ""

                Expect.equal
                    missing.StatusCode
                    HttpStatusCode.BadRequest
                    "a missing today is 400"

                let! malformed = getDashboard app.Client "?today=14/10/2026"

                Expect.equal
                    malformed.StatusCode
                    HttpStatusCode.BadRequest
                    "a malformed today is 400"

                let! body =
                    malformed.Content.ReadAsStringAsync () |> Async.AwaitTask

                Expect.stringContains body "'today'" "names the parameter"
            }
        ]
