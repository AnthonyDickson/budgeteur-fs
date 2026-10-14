namespace Budgeteur.Tests.Dashboard

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Feature.Dashboard
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
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withDashboard
        )

    let private getDashboard (client : HttpClient) (query : string) =
        client.GetAsync (ReadDashboard.Path + query) |> Async.AwaitTask

    let private onToday = "?today=2026-10-14"

    let private createTransaction
        (client : HttpClient)
        (date : DateOnly)
        (amount : decimal)
        =
        TestHttp.postJson
            client
            CreateTransaction.Path
            ({
                Amount = amount
                Description = "Spending"
                Date = date
                IsTransfer = false
                TagId = None
                AccountId = None
            }
            : CreateTransaction.CreateTransactionRequest)
        |> Async.AwaitTask
        |> Async.Ignore

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
