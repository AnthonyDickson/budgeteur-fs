namespace Budgeteur.Tests.BalanceSheet

/// <summary>Closing and reopening items and accounts, and how closed lines
/// appear on the balance sheet. See decision 4 in docs/reports.md.</summary>
module ClosingTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Account
    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    /// Create an item valued on 1 January 2026 and return its id.
    let private createItem
        (client : HttpClient)
        (name : string)
        (value : decimal)
        : Async<Guid> =
        async {
            let request : CreateBalanceSheetItemRequest = {
                Name = name
                Side = "Asset"
                Term = "NonCurrent"
                Value = value
                AsOf = DateOnly (2026, 1, 1)
            }

            let! response =
                TestHttp.postJson client CreateBalanceSheetItem.Path request
                |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.Created
                "create should return 201"

            let! item = TestHttp.readJson<BalanceSheetItemResponse> response
            return item.Id
        }

    let private getSheetBody
        (client : HttpClient)
        : Async<ReadBalanceSheet.BalanceSheetResponse> =
        async {
            let! response =
                client.GetAsync ReadBalanceSheet.Path |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "read should return 200"

            return!
                TestHttp.readJson<ReadBalanceSheet.BalanceSheetResponse>
                    response
        }

    [<Tests>]
    let tests =
        testList "Closing" [
            testCaseAsync "closed lines leave the sheet and are listed apart"
            <| async {
                let now = DateTime (2026, 3, 8, 23, 0, 0, DateTimeKind.Utc)
                let clock : Clock = fun () -> DateTimeOffset now

                use app =
                    TestApp.create (
                        TestAppConfig.empty
                        |> TestAppConfig.withBalanceSheet clock
                        |> TestAppConfig.withAccounts clock
                        |> TestAppConfig.withTransactions
                    )

                let! house = createItem app.Client "House" 400000m

                let! _ = createItem app.Client "Car" 9000m

                let! card =
                    Seed.account
                        app.Client
                        "Credit card"
                        (Some (DateOnly (2026, 3, 1), -400m))

                let closeItem (closedOn : DateOnly) =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath CloseBalanceSheetItem.Path house)
                        ({ ClosedOn = closedOn }
                        : CloseBalanceSheetItem.CloseBalanceSheetItemRequest)
                    |> Async.AwaitTask

                let closeAccount (closedOn : DateOnly) =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath CloseAccount.Path card)
                        ({ ClosedOn = closedOn }
                        : CloseAccount.CloseAccountRequest)
                    |> Async.AwaitTask

                // When: the house is sold and the card closed.
                let! sold = closeItem (DateOnly (2026, 3, 5))
                Expect.equal sold.StatusCode HttpStatusCode.OK "closing is 200"
                let! closed = closeAccount (DateOnly (2026, 3, 6))

                Expect.equal
                    closed.StatusCode
                    HttpStatusCode.OK
                    "closing an account is 200"

                // When: transactions on the card are dated on and after its
                // close date.
                for day in [ 6; 7; 8 ] do
                    do!
                        Seed.transaction
                            app.Client
                            card
                            (DateOnly (2026, 3, day))
                            -10m

                // When: the sold house's details are edited.
                let! edited =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateBalanceSheetItem.Path house)
                        ({ Name = "House"; Term = "NonCurrent" }
                        : UpdateBalanceSheetItemRequest)
                    |> Async.AwaitTask

                Expect.equal
                    edited.StatusCode
                    HttpStatusCode.OK
                    "editing is 200"

                // Then: the closed lines leave the sheet and its totals, and
                // are listed apart with their close dates. Editing kept the
                // house closed.
                let! sheet = getSheetBody app.Client

                Expect.equal
                    (sheet.Items |> List.map _.Name)
                    [ "Car" ]
                    "the sold item leaves the sheet"

                Expect.isEmpty sheet.Accounts "the closed account leaves it"
                Expect.equal sheet.NetWorth 9000m "only the car counts"

                Expect.equal
                    (sheet.ClosedItems |> List.map (fun i -> i.Id, i.ClosedOn))
                    [ house, Some (DateOnly (2026, 3, 5)) ]
                    "the sold item is listed with its close date"

                Expect.equal
                    (sheet.ClosedAccounts
                     |> List.map (fun a ->
                         a.Id, a.ClosedOn, a.TransactionsAfterClose))
                    [
                        card,
                        DateOnly (2026, 3, 6),
                        Some {
                            Count = 2
                            Latest = DateOnly (2026, 3, 8)
                        }
                    ]
                    "with the transactions after its close date, not on it"

                // Then: the account's own read carries them too, for its
                // details page.
                let! read =
                    app.Client.GetAsync (
                        TestHttp.itemPath ReadAccount.Path card
                    )
                    |> Async.AwaitTask

                let! read = TestHttp.readJson<AccountResponse> read

                Expect.equal
                    read.TransactionsAfterClose
                    (Some {
                        Count = 2
                        Latest = DateOnly (2026, 3, 8)
                    })
                    "the account read flags the transactions"

                // When: the house and the card are reopened.
                let! reopened =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath ReopenBalanceSheetItem.Path house
                    )
                    |> Async.AwaitTask

                Expect.equal
                    reopened.StatusCode
                    HttpStatusCode.NoContent
                    "reopening is 204"

                let! reopenedAccount =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath ReopenAccount.Path card
                    )
                    |> Async.AwaitTask

                Expect.equal
                    reopenedAccount.StatusCode
                    HttpStatusCode.NoContent
                    "reopening an account is 204"

                // Then: they are back on the sheet with their balances.
                let! sheet = getSheetBody app.Client
                Expect.equal sheet.NetWorth 408600m "the house and card count"
                Expect.isEmpty sheet.ClosedItems "no item is closed"
                Expect.isEmpty sheet.ClosedAccounts "no account is closed"

                // Then: a close date after tomorrow is rejected.
                let! future = closeItem (DateOnly (2026, 3, 10))

                Expect.equal
                    future.StatusCode
                    HttpStatusCode.BadRequest
                    "an item closed in the future is rejected"

                let! futureAccount = closeAccount (DateOnly (2026, 3, 10))

                Expect.equal
                    futureAccount.StatusCode
                    HttpStatusCode.BadRequest
                    "an account closed in the future is rejected"

                // Then: another user can neither close nor reopen them.
                use otherUser = app.ClientForUser "other-user"

                let! othersClose =
                    TestHttp.putJson
                        otherUser
                        (TestHttp.itemPath CloseBalanceSheetItem.Path house)
                        ({ ClosedOn = DateOnly (2026, 3, 5) }
                        : CloseBalanceSheetItem.CloseBalanceSheetItemRequest)
                    |> Async.AwaitTask

                Expect.equal
                    othersClose.StatusCode
                    HttpStatusCode.NotFound
                    "another user's close is 404"

                let! othersReopen =
                    otherUser.DeleteAsync (
                        TestHttp.itemPath ReopenAccount.Path card
                    )
                    |> Async.AwaitTask

                Expect.equal
                    othersReopen.StatusCode
                    HttpStatusCode.NotFound
                    "another user's reopen is 404"
            }

        ]
