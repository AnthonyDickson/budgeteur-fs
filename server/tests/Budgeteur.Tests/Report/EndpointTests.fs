namespace Budgeteur.Tests.Report

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Feature.Report
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
            |> TestAppConfig.withAccounts clock
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withReports
        )

    let private getReport (client : HttpClient) (query : string) =
        client.GetAsync (ReadReport.Path + query) |> Async.AwaitTask

    let private march = "?frequency=Monthly&today=2026-10-14&date=2026-03-10"

    // The figures are covered by ComputeTests. These tests cover what only
    // the endpoint can get wrong: the query, loading, scoping, and encoding.
    [<Tests>]
    let tests =
        testList "Report endpoint" [
            testCaseAsync "a report is read from the user's data"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! house =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        ({
                            Name = "House"
                            Side = "Asset"
                            Term = "NonCurrent"
                            Value = 400000m
                            AsOf = DateOnly (2026, 1, 10)
                        }
                        : CreateBalanceSheetItemRequest)
                    |> Async.AwaitTask

                let! house = TestHttp.readJson<BalanceSheetItemResponse> house

                let! _ =
                    TestHttp.postJson
                        app.Client
                        (TestHttp.itemPath RecordItemObservation.Path house.Id)
                        ({
                            Value = 410000m
                            AsOf = DateOnly (2026, 3, 20)
                        }
                        : ItemObservationRequest)
                    |> Async.AwaitTask

                let! _ =
                    TestHttp.postJson
                        app.Client
                        CreateTransaction.Path
                        ({
                            Amount = -2000m
                            Description = "Rent"
                            Date = DateOnly (2026, 3, 5)
                            IsTransfer = false
                            TagId = None
                            AccountId = None
                        }
                        : CreateTransaction.CreateTransactionRequest)
                    |> Async.AwaitTask

                // When: March is read.
                let! response = getReport app.Client march
                Expect.equal response.StatusCode HttpStatusCode.OK "200"

                let! body =
                    response.Content.ReadAsStringAsync () |> Async.AwaitTask

                let! report = TestHttp.readJson<ReportResponse> response

                // Then: it is drawn from the user's observations and
                // transactions.
                Expect.equal report.Label "March 2026" "the label"
                Expect.equal report.Opening.NetWorth 400000m "opening"
                Expect.equal report.Closing.NetWorth 410000m "closing"
                Expect.equal report.ChangeInNetWorth (Some 10000m) "change"

                Expect.equal
                    report.OtherChanges
                    (Some 12000m)
                    "10k more net worth despite 2k spent"

                Expect.equal report.Expenses 2000m "the rent"
                Expect.isTrue report.HasPrevious "February has a report"
                Expect.isTrue report.HasNext "April has a report"

                Expect.stringContains
                    body
                    "\"changeInNetWorth\":\"10000"
                    "money is serialised as a string"

                // Then: the default is the latest complete period, September.
                let! latest =
                    getReport app.Client "?frequency=Monthly&today=2026-10-14"

                let! latest = TestHttp.readJson<ReportResponse> latest
                Expect.equal latest.Label "September 2026" "latest complete"

                // Then: another user has none of it.
                let! foreign = getReport otherUser march

                Expect.equal
                    foreign.StatusCode
                    HttpStatusCode.NotFound
                    "another user has no data in March"
            }

            testCaseAsync "invalid queries are reported together"
            <| async {
                use app = newApp ()

                let! response = getReport app.Client "?frequency=Weekly&date=x"

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.BadRequest
                    "a bad query is 400"

                let! body =
                    response.Content.ReadAsStringAsync () |> Async.AwaitTask

                Expect.stringContains body "Weekly" "names the frequency"
                Expect.stringContains body "'today'" "names the missing today"
                Expect.stringContains body "'date'" "names the bad date"
            }

            testCaseAsync "a period after today has no report"
            <| async {
                use app = newApp ()

                let! response =
                    getReport
                        app.Client
                        "?frequency=Monthly&today=2026-10-14&date=2026-11-01"

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.NotFound
                    "the future has no report"
            }
        ]
