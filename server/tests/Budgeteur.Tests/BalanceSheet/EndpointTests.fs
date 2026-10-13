namespace Budgeteur.Tests.BalanceSheet

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Account
    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    /// A valid create payload. No id is supplied, matching the
    /// server-owned-id contract.
    let private request
        (name : string)
        (side : string)
        (term : string)
        (value : decimal)
        : CreateBalanceSheetItemRequest = {
        Name = name
        Side = side
        Term = term
        Value = value
        AsOf = DateOnly (2026, 1, 1)
    }

    let private details
        (name : string)
        (term : string)
        : UpdateBalanceSheetItemRequest = {
        Name = name
        Term = term
        ClosedOn = None
    }

    let private observation
        (value : decimal)
        (asOf : DateOnly)
        : ItemObservationRequest = { Value = value; AsOf = asOf }

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty |> TestAppConfig.withBalanceSheet Clock.system
        )

    /// A clock stopped at the given instant, so the as-of date bound is known.
    let private fixedClock (instant : DateTimeOffset) : Clock =
        fun () -> instant

    /// Create an item and return its server-assigned id.
    let private createItem
        (client : HttpClient)
        (payload : CreateBalanceSheetItemRequest)
        : Async<Guid> =
        async {
            let! response =
                TestHttp.postJson client CreateBalanceSheetItem.Path payload
                |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.Created
                "create should return 201"

            let! item = TestHttp.readJson<BalanceSheetItemResponse> response
            return item.Id
        }

    let private getSheet (client : HttpClient) : Async<HttpResponseMessage> =
        client.GetAsync ReadBalanceSheet.Path |> Async.AwaitTask

    let private getSheetBody
        (client : HttpClient)
        : Async<ReadBalanceSheet.BalanceSheetResponse> =
        async {
            let! response = getSheet client

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "read should return 200"

            return!
                TestHttp.readJson<ReadBalanceSheet.BalanceSheetResponse>
                    response
        }

    let private statusOf (response : HttpResponseMessage) = response.StatusCode

    let private deleteItem
        (client : HttpClient)
        (id : Guid)
        : Async<HttpStatusCode> =
        async {
            let! response =
                client.DeleteAsync (
                    TestHttp.itemPath DeleteBalanceSheetItem.Path id
                )
                |> Async.AwaitTask

            return statusOf response
        }

    let private updateItem
        (client : HttpClient)
        (id : Guid)
        (payload : UpdateBalanceSheetItemRequest)
        : Async<HttpStatusCode> =
        async {
            let! response =
                TestHttp.putJson
                    client
                    (TestHttp.itemPath UpdateBalanceSheetItem.Path id)
                    payload
                |> Async.AwaitTask

            return statusOf response
        }

    let private recordValue
        (client : HttpClient)
        (id : Guid)
        (payload : ItemObservationRequest)
        : Async<HttpResponseMessage> =
        TestHttp.postJson
            client
            (TestHttp.itemPath RecordItemObservation.Path id)
            payload
        |> Async.AwaitTask

    /// The item's value and as-of date on the sheet.
    let private currentValue
        (client : HttpClient)
        (id : Guid)
        : Async<decimal * DateOnly> =
        async {
            let! sheet = getSheetBody client

            match sheet.Items |> List.tryFind (fun item -> item.Id = id) with
            | Some item -> return item.Value, item.AsOf
            | None -> return failtestf "Item %O is not on the sheet" id
        }

    let private getItem
        (client : HttpClient)
        (id : Guid)
        : Async<HttpStatusCode> =
        async {
            let! response =
                client.GetAsync (TestHttp.itemPath ReadBalanceSheetItem.Path id)
                |> Async.AwaitTask

            return statusOf response
        }

    /// Four items, one per side and term, so every total has a distinguishable
    /// value.
    let private createOneOfEachSideAndTerm (client : HttpClient) : Async<unit> =
        async {
            let! _ =
                createItem client (request "Chequing" "Asset" "Current" 2000m)

            let! _ =
                createItem client (request "House" "Asset" "NonCurrent" 400000m)

            let! _ =
                createItem
                    client
                    (request "Credit card" "Liability" "Current" 1500m)

            let! _ =
                createItem
                    client
                    (request "Mortgage" "Liability" "NonCurrent" 300000m)

            return ()
        }

    [<Tests>]
    let tests =
        testList "BalanceSheet" [
            testCaseAsync "the read surface is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                // Given: an item owned by the default test user.
                let! id =
                    createItem
                        app.Client
                        (request "Chequing" "Asset" "Current" 2000m)

                // Then: the owner sees the sheet and the item.
                let! ownedSheet = getSheet app.Client

                Expect.equal
                    ownedSheet.StatusCode
                    HttpStatusCode.OK
                    "the owner should see their sheet"

                let! ownedList =
                    app.Client.GetAsync ReadAllBalanceSheetItems.Path
                    |> Async.AwaitTask

                Expect.equal
                    ownedList.StatusCode
                    HttpStatusCode.OK
                    "the owner's item list should be 200"

                let! ownedItems =
                    TestHttp.readJson<BalanceSheetItemResponse list> ownedList

                Expect.equal
                    (List.map (fun item -> item.Id) ownedItems)
                    [ id ]
                    "the owner's list should hold their item"

                // Then: another user sees none of it.
                let! otherSheet = getSheetBody otherUser

                Expect.isEmpty
                    otherSheet.Items
                    "another user's sheet should be empty"

                let! otherItem = getItem otherUser id

                Expect.equal
                    otherItem
                    HttpStatusCode.NotFound
                    "another user's item read should be 404"

                let! otherList =
                    otherUser.GetAsync ReadAllBalanceSheetItems.Path
                    |> Async.AwaitTask

                Expect.equal
                    otherList.StatusCode
                    HttpStatusCode.OK
                    "another user's item list should still be 200"

                let! otherItems =
                    TestHttp.readJson<BalanceSheetItemResponse list> otherList

                Expect.equal
                    otherItems
                    []
                    "another user's item list should be empty"

                let! deleteStatus = deleteItem otherUser id

                Expect.equal
                    deleteStatus
                    HttpStatusCode.NotFound
                    "another user's delete should be 404"

                // Then: the item is untouched.
                let! stillThere = getItem app.Client id

                Expect.equal
                    stillThere
                    HttpStatusCode.OK
                    "the item should survive another user's delete"
            }

            testCaseAsync
                "the read assembles, aggregates, and encodes the sheet"
            <| async {
                use app = newApp ()

                // Given: a user with no items has an empty sheet, not a
                // missing one.
                let! empty = getSheetBody app.Client
                Expect.isEmpty empty.Items "a new user's sheet should be empty"
                Expect.equal empty.NetWorth 0m "an empty sheet has no net worth"

                // Given: one item per side and term.
                do! createOneOfEachSideAndTerm app.Client

                // When: the sheet is read.
                let! response = getSheet app.Client

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.OK
                    "the sheet should be readable"

                let! body =
                    response.Content.ReadAsStringAsync () |> Async.AwaitTask

                let! sheet =
                    TestHttp.readJson<ReadBalanceSheet.BalanceSheetResponse>
                        response

                // Then: every item is present.
                Expect.equal
                    (List.length sheet.Items)
                    4
                    "every item should be returned"

                Expect.equal
                    (sheet.Items
                     |> List.map (fun item -> item.Name)
                     |> List.sort)
                    [ "Chequing"; "Credit card"; "House"; "Mortgage" ]
                    "every item should be returned once"

                // Then: four items make each total distinguishable, so a
                // mis-assignment fails.
                Expect.equal sheet.TotalCurrentAssets 2000m "current assets"

                Expect.equal
                    sheet.TotalNonCurrentAssets
                    400000m
                    "non-current assets"

                Expect.equal
                    sheet.TotalCurrentLiabilities
                    1500m
                    "current liabilities"

                Expect.equal
                    sheet.TotalNonCurrentLiabilities
                    300000m
                    "non-current liabilities"

                Expect.equal sheet.TotalAssets 402000m "total assets"
                Expect.equal sheet.TotalLiabilities 301500m "total liabilities"
                Expect.equal sheet.NetWorth 100500m "net worth"
                Expect.equal sheet.WorkingCapital 500m "working capital"

                // Then: money and enums cross the wire as strings.
                Expect.stringContains
                    body
                    "\"totalAssets\":\""
                    "money should be serialised as a JSON string"

                Expect.stringContains
                    body
                    "\"side\":\"Asset\""
                    "sides should be serialised as strings"

                Expect.stringContains
                    body
                    "\"term\":\"NonCurrent\""
                    "terms should be serialised as strings"
            }

            testCaseAsync
                "accounts are lines on the sheet by the sign of balance"
            <| async {
                use app =
                    TestApp.create (
                        TestAppConfig.empty
                        |> TestAppConfig.withBalanceSheet Clock.system
                        |> TestAppConfig.withAccounts Clock.system
                    )

                use otherUser = app.ClientForUser "other-user"

                do! createOneOfEachSideAndTerm app.Client

                let! everyday =
                    Seed.account
                        app.Client
                        "Everyday"
                        (Some (DateOnly (2026, 3, 1), 1000m))

                let! card =
                    Seed.account
                        app.Client
                        "Credit card"
                        (Some (DateOnly (2026, 3, 2), -400m))

                let! unknown = Seed.account app.Client "New card" None

                let! sheet = getSheetBody app.Client

                // Then: a held balance is an asset and an owed one a
                // liability, with its magnitude and as-of date.
                Expect.equal
                    (sheet.Accounts
                     |> List.map (fun line ->
                         line.Id, line.Side, line.Balance, line.AsOf))
                    [
                        card, "Liability", 400m, DateOnly (2026, 3, 2)
                        everyday, "Asset", 1000m, DateOnly (2026, 3, 1)
                    ]
                    "the accounts with a known balance are lines, by name"

                Expect.equal
                    (sheet.UnknownBalances |> List.map _.Id)
                    [ unknown ]
                    "the account without a balance is listed as unknown"

                // Then: the items' totals (from createOneOfEachSideAndTerm)
                // gain the account lines, and the unknown balance adds
                // nothing.
                Expect.equal sheet.TotalCurrentAssets 3000m "current assets"

                Expect.equal
                    sheet.TotalCurrentLiabilities
                    1900m
                    "current liabilities"

                Expect.equal sheet.NetWorth 101100m "net worth"
                Expect.equal sheet.WorkingCapital 1100m "working capital"

                // When: a balance dated before the current one is recorded.
                do! Seed.balance app.Client everyday (DateOnly (2026, 2, 1)) 50m

                // Then: the newer balance stays current.
                let! sheet = getSheetBody app.Client

                Expect.equal
                    (sheet.Accounts
                     |> List.filter (fun line -> line.Id = everyday)
                     |> List.map (fun line -> line.Balance, line.AsOf))
                    [ 1000m, DateOnly (2026, 3, 1) ]
                    "an older balance does not replace a newer one"

                // Then: another user's sheet has none of the accounts.
                let! otherSheet = getSheetBody otherUser
                Expect.isEmpty otherSheet.Accounts "no account lines"
                Expect.isEmpty otherSheet.UnknownBalances "no unknown balances"
            }

            testCaseAsync "closed lines leave the sheet and are listed apart"
            <| async {
                let now = DateTime (2026, 3, 8, 23, 0, 0, DateTimeKind.Utc)
                let clock = fixedClock (DateTimeOffset now)

                use app =
                    TestApp.create (
                        TestAppConfig.empty
                        |> TestAppConfig.withBalanceSheet clock
                        |> TestAppConfig.withAccounts clock
                    )

                let! house =
                    createItem
                        app.Client
                        (request "House" "Asset" "NonCurrent" 400000m)

                let! _ =
                    createItem
                        app.Client
                        (request "Car" "Asset" "NonCurrent" 9000m)

                let! card =
                    Seed.account
                        app.Client
                        "Credit card"
                        (Some (DateOnly (2026, 3, 1), -400m))

                let closeAccount (closedOn : DateOnly option) =
                    let request : UpdateAccount.UpdateAccountRequest = {
                        Name = "Credit card"
                        Number = None
                        Term = "Current"
                        ClosedOn = closedOn
                    }

                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateAccount.Path card)
                        request
                    |> Async.AwaitTask

                // When: the house is sold and the card closed.
                let! sold =
                    updateItem app.Client house {
                        details "House" "NonCurrent" with
                            ClosedOn = Some (DateOnly (2026, 3, 5))
                    }

                Expect.equal sold HttpStatusCode.OK "closing an item is 200"
                let! closed = closeAccount (Some (DateOnly (2026, 3, 6)))

                Expect.equal
                    closed.StatusCode
                    HttpStatusCode.OK
                    "closing an account is 200"

                // Then: they leave the sheet and its totals, and are listed
                // apart with their close dates.
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
                     |> List.map (fun a -> a.Id, a.ClosedOn))
                    [ card, DateOnly (2026, 3, 6) ]
                    "the closed account is listed with its close date"

                // When: the house is reopened.
                let! reopened =
                    updateItem app.Client house (details "House" "NonCurrent")

                Expect.equal reopened HttpStatusCode.OK "reopening is 200"

                // Then: it is back on the sheet with its value.
                let! sheet = getSheetBody app.Client
                Expect.equal sheet.NetWorth 409000m "the house counts again"
                Expect.isEmpty sheet.ClosedItems "no item is closed"

                // Then: a close date after tomorrow is rejected.
                let! future =
                    updateItem app.Client house {
                        details "House" "NonCurrent" with
                            ClosedOn = Some (DateOnly (2026, 3, 10))
                    }

                Expect.equal
                    future
                    HttpStatusCode.BadRequest
                    "an item closed in the future is rejected"

                let! futureAccount =
                    closeAccount (Some (DateOnly (2026, 3, 10)))

                Expect.equal
                    futureAccount.StatusCode
                    HttpStatusCode.BadRequest
                    "an account closed in the future is rejected"
            }

            testCaseAsync "uniqueness includes the term"
            <| async {
                use app = newApp ()

                // Given: an existing item.
                let! existing =
                    createItem
                        app.Client
                        (request "Chequing" "Asset" "Current" 2000m)

                // When: an identical item is created.
                let! duplicate =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        (request "Chequing" "Asset" "Current" 999m)
                    |> Async.AwaitTask

                // Then: the conflict is reported as a validation failure, not a
                // 500.
                Expect.equal
                    duplicate.StatusCode
                    HttpStatusCode.BadRequest
                    "an identical item should be rejected"

                // When: the same name is used with a different term.
                let! otherTerm =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        (request "Chequing" "Asset" "NonCurrent" 999m)
                    |> Async.AwaitTask

                // Then: it is a different item.
                Expect.equal
                    otherTerm.StatusCode
                    HttpStatusCode.Created
                    "the term is part of the uniqueness key"

                // When: an update moves an item onto another item's key.
                let! collision =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateBalanceSheetItem.Path existing)
                        (details "Chequing" "NonCurrent")
                    |> Async.AwaitTask

                Expect.equal
                    collision.StatusCode
                    HttpStatusCode.BadRequest
                    "an update onto another item's key should be rejected"

                // When: an update keeps its own key.
                let! self =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateBalanceSheetItem.Path existing)
                        (details "Chequing" "Current")
                    |> Async.AwaitTask

                Expect.equal
                    self.StatusCode
                    HttpStatusCode.OK
                    "an update onto itself should be accepted"
            }

            testCaseAsync "deleting the last item leaves an empty sheet"
            <| async {
                use app = newApp ()

                // Given: a sheet with a single item.
                let! id =
                    createItem
                        app.Client
                        (request "Chequing" "Asset" "Current" 2000m)

                // When: the item is deleted.
                let! deleted = deleteItem app.Client id

                Expect.equal
                    deleted
                    HttpStatusCode.NoContent
                    "delete should return 204"

                // Then: the sheet is empty, with zero totals.
                let! sheet = getSheetBody app.Client
                Expect.equal sheet.Items [] "the deleted item should be gone"

                Expect.equal
                    sheet.TotalAssets
                    0m
                    "an itemless sheet has no assets"

                Expect.equal
                    sheet.NetWorth
                    0m
                    "an itemless sheet has no net worth"

                // Then: a second delete reports the item is gone.
                let! again = deleteItem app.Client id

                Expect.equal
                    again
                    HttpStatusCode.NotFound
                    "a second delete should return 404"

                let! missing = getItem app.Client id

                Expect.equal
                    missing
                    HttpStatusCode.NotFound
                    "the deleted item should not be readable"
            }

            testCaseAsync "invalid input is reported as a bad request"
            <| async {
                use app = newApp ()

                // The validation rules themselves are covered by the domain
                // tests.
                let! response =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        (request "Chequing" "Asset" "Current" -1m)
                    |> Async.AwaitTask

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.BadRequest
                    "a negative value should be rejected"

                // Nothing was written.
                let! sheet = getSheetBody app.Client
                Expect.isEmpty sheet.Items "a rejected write should add no item"
            }

            testCaseAsync "an item's value is its latest observation"
            <| async {
                let now = DateTime (2026, 3, 8, 23, 0, 0, DateTimeKind.Utc)

                use app =
                    TestApp.create (
                        TestAppConfig.empty
                        |> TestAppConfig.withBalanceSheet (
                            fixedClock (DateTimeOffset now)
                        )
                    )

                use otherUser = app.ClientForUser "other-user"

                // Given: an item created with its first value.
                let! id =
                    createItem
                        app.Client
                        (request "House" "Asset" "NonCurrent" 2000m)

                let! first = currentValue app.Client id

                Expect.equal
                    first
                    (2000m, DateOnly (2026, 1, 1))
                    "the first value is current"

                // When: a newer value is recorded.
                let! newer =
                    recordValue
                        app.Client
                        id
                        (observation 2500m (DateOnly (2026, 2, 1)))

                Expect.equal newer.StatusCode HttpStatusCode.OK "record is 200"

                let! recorded =
                    TestHttp.readJson<BalanceSheetItemResponse> newer

                Expect.equal
                    (recorded.Value, recorded.AsOf)
                    (2500m, DateOnly (2026, 2, 1))
                    "the response has the item's current value"

                // When: an older value is recorded.
                let! _ =
                    recordValue
                        app.Client
                        id
                        (observation 1000m (DateOnly (2026, 1, 15)))

                // Then: the newer value stays current.
                let! afterOlder = currentValue app.Client id

                Expect.equal
                    afterOlder
                    (2500m, DateOnly (2026, 2, 1))
                    "an older value does not replace a newer one"

                // When: a value is recorded on a date that has one.
                let! _ =
                    recordValue
                        app.Client
                        id
                        (observation 2600m (DateOnly (2026, 2, 1)))

                // Then: it replaces the value on that date.
                let! corrected = currentValue app.Client id

                Expect.equal
                    corrected
                    (2600m, DateOnly (2026, 2, 1))
                    "a value on the same date replaces it"

                // When: the item's details change.
                let! updated =
                    updateItem app.Client id (details "Home" "NonCurrent")

                Expect.equal updated HttpStatusCode.OK "update is 200"

                // Then: its value does not.
                let! afterUpdate = currentValue app.Client id

                Expect.equal
                    afterUpdate
                    (2600m, DateOnly (2026, 2, 1))
                    "an update keeps the item's value"

                // Then: invalid values are rejected, and another user's item
                // is not found.
                let! negative =
                    recordValue
                        app.Client
                        id
                        (observation -1m (DateOnly (2026, 3, 1)))

                Expect.equal
                    negative.StatusCode
                    HttpStatusCode.BadRequest
                    "a negative value is rejected"

                let! future =
                    recordValue
                        app.Client
                        id
                        (observation 1m (DateOnly (2026, 3, 10)))

                Expect.equal
                    future.StatusCode
                    HttpStatusCode.BadRequest
                    "a value dated after tomorrow is rejected"

                let! foreign =
                    recordValue
                        otherUser
                        id
                        (observation 1m (DateOnly (2026, 3, 1)))

                Expect.equal
                    foreign.StatusCode
                    HttpStatusCode.NotFound
                    "another user's item is not found"

                let! unchanged = currentValue app.Client id

                Expect.equal
                    unchanged
                    (2600m, DateOnly (2026, 2, 1))
                    "rejected writes leave the value alone"
            }

            testCaseAsync "an item keeps its as-of date, which cannot be future"
            <| async {
                let now = DateTime (2026, 3, 8, 23, 0, 0, DateTimeKind.Utc)
                let clock = fixedClock (DateTimeOffset now)

                use app =
                    TestApp.create (
                        TestAppConfig.empty
                        |> TestAppConfig.withBalanceSheet clock
                    )

                // Given: an item dated the day after the server's UTC date,
                // which a client ahead of UTC may call today.
                let tomorrow = {
                    request "Chequing" "Asset" "Current" 2000m with
                        AsOf = DateOnly (2026, 3, 9)
                }

                let! id = createItem app.Client tomorrow

                // Then: the sheet reports the item's as-of date.
                let! sheet = getSheetBody app.Client

                Expect.equal
                    (sheet.Items |> List.map (fun item -> item.AsOf))
                    [ DateOnly (2026, 3, 9) ]
                    "the item should keep its as-of date"

                // When: a later date is written.
                let future = {
                    tomorrow with
                        AsOf = DateOnly (2026, 3, 10)
                }

                let! created =
                    TestHttp.postJson app.Client CreateBalanceSheetItem.Path {
                        future with
                            Name = "Savings"
                    }
                    |> Async.AwaitTask

                // Then: it is rejected.
                Expect.equal
                    created.StatusCode
                    HttpStatusCode.BadRequest
                    "a create dated after tomorrow should be rejected"

                let! sheet = getSheetBody app.Client

                Expect.equal
                    (sheet.Items |> List.map _.Id)
                    [ id ]
                    "the rejected create should add no item"
            }


        ]
