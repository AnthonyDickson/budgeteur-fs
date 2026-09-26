namespace Budgeteur.Tests.BalanceSheet

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    /// Fill the Oxpecker routef `{%O:guid}` placeholder in an item path with a concrete id.
    let private routefPath (path : string) (id : Guid) =
        path.Replace ("{%O:guid}", id.ToString ())

    /// A valid create or update payload. No id is supplied, matching the server-owned-id contract.
    let private request
        (name : string)
        (kind : string)
        (term : string)
        (balance : decimal)
        : WriteBalanceSheetItemRequest =
        {
            Name = name
            Kind = kind
            Term = term
            Balance = balance
        }

    let private newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withBalanceSheet Clock.system)

    /// A clock a test can move, so a refreshed statement date is distinguishable
    /// from a stale one. Returns the clock and a function that sets the instant.
    let private testClock (start : DateTimeOffset) : Clock * (DateTimeOffset -> unit) =
        let instant = ref start
        (fun () -> instant.Value), (fun next -> instant.Value <- next)

    /// Fail the test with the decoder's message rather than an opaque null.
    let private orFail (result : Result<'T, string>) : Async<'T> =
        async {
            match result with
            | Ok value -> return value
            | Error error -> return failtest error
        }

    let private itemId (response : HttpResponseMessage) : Async<Guid> =
        async {
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
            let! item = Decode.fromStringAuto<BalanceSheetItemResponse> body |> orFail
            return item.Id
        }

    /// Create an item and return its server-assigned id.
    let private createItem (client : HttpClient) (payload : WriteBalanceSheetItemRequest) : Async<Guid> =
        async {
            let! response = TestHttp.postJson client CreateBalanceSheetItem.Path payload |> Async.AwaitTask
            Expect.equal response.StatusCode HttpStatusCode.Created "create should return 201"
            return! itemId response
        }

    let private getSheet (client : HttpClient) : Async<HttpResponseMessage> =
        client.GetAsync ReadBalanceSheet.Path |> Async.AwaitTask

    let private getSheetBody (client : HttpClient) : Async<ReadBalanceSheet.BalanceSheetResponse> =
        async {
            let! response = getSheet client
            Expect.equal response.StatusCode HttpStatusCode.OK "read should return 200"
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
            return! Decode.fromStringAuto<ReadBalanceSheet.BalanceSheetResponse> body |> orFail
        }

    let private statusOf (response : HttpResponseMessage) = response.StatusCode

    let private deleteItem (client : HttpClient) (id : Guid) : Async<HttpStatusCode> =
        async {
            let! response =
                client.DeleteAsync (routefPath DeleteBalanceSheetItem.Path id)
                |> Async.AwaitTask

            return statusOf response
        }

    let private updateItem
        (client : HttpClient)
        (id : Guid)
        (payload : WriteBalanceSheetItemRequest)
        : Async<HttpStatusCode> =
        async {
            let! response =
                TestHttp.putJson client (routefPath UpdateBalanceSheetItem.Path id) payload
                |> Async.AwaitTask

            return statusOf response
        }

    let private getItem (client : HttpClient) (id : Guid) : Async<HttpStatusCode> =
        async {
            let! response = client.GetAsync (routefPath ReadBalanceSheetItem.Path id) |> Async.AwaitTask

            return statusOf response
        }

    /// Four items, one per kind and term, so every total has a distinguishable value.
    let private createOneOfEachKindAndTerm (client : HttpClient) : Async<unit> =
        async {
            let! _ = createItem client (request "Chequing" "Asset" "Current" 2000m)
            let! _ = createItem client (request "House" "Asset" "NonCurrent" 400000m)
            let! _ = createItem client (request "Credit card" "Liability" "Current" 1500m)
            let! _ = createItem client (request "Mortgage" "Liability" "NonCurrent" 300000m)
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
                let! id = createItem app.Client (request "Chequing" "Asset" "Current" 2000m)

                // Then: the owner sees the sheet and the item.
                let! ownedSheet = getSheet app.Client
                Expect.equal ownedSheet.StatusCode HttpStatusCode.OK "the owner should see their sheet"

                let! ownedList = app.Client.GetAsync ReadAllBalanceSheetItems.Path |> Async.AwaitTask
                Expect.equal ownedList.StatusCode HttpStatusCode.OK "the owner's item list should be 200"

                let! listBody = ownedList.Content.ReadAsStringAsync () |> Async.AwaitTask
                let! ownedItems = Decode.fromStringAuto<BalanceSheetItemResponse list> listBody |> orFail

                Expect.equal
                    (List.map (fun item -> item.Id) ownedItems)
                    [ id ]
                    "the owner's list should hold their item"

                // Then: another user sees none of it.
                let! otherSheet = getSheet otherUser
                Expect.equal otherSheet.StatusCode HttpStatusCode.NotFound "another user's sheet should be 404"

                let! otherItem = getItem otherUser id
                Expect.equal otherItem HttpStatusCode.NotFound "another user's item read should be 404"

                let! otherList = otherUser.GetAsync ReadAllBalanceSheetItems.Path |> Async.AwaitTask
                Expect.equal otherList.StatusCode HttpStatusCode.OK "another user's item list should still be 200"

                let! otherListBody = otherList.Content.ReadAsStringAsync () |> Async.AwaitTask
                let! otherItems = Decode.fromStringAuto<BalanceSheetItemResponse list> otherListBody |> orFail

                Expect.equal otherItems [] "another user's item list should be empty"

                let! deleteStatus = deleteItem otherUser id
                Expect.equal deleteStatus HttpStatusCode.NotFound "another user's delete should be 404"

                // Then: the item is untouched.
                let! stillThere = getItem app.Client id
                Expect.equal stillThere HttpStatusCode.OK "the item should survive another user's delete"
            }

            testCaseAsync "the read assembles, aggregates, and encodes the sheet"
            <| async {
                use app = newApp ()
                let before = DateTime.UtcNow

                // Given: no sheet yet, because the sheet is created on the first item write.
                let! empty = getSheet app.Client
                Expect.equal empty.StatusCode HttpStatusCode.NotFound "an unwritten sheet should be 404"

                // Given: one item per kind and term.
                do! createOneOfEachKindAndTerm app.Client

                // When: the sheet is read.
                let! response = getSheet app.Client
                Expect.equal response.StatusCode HttpStatusCode.OK "the sheet should be readable"
                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
                let! sheet = Decode.fromStringAuto<ReadBalanceSheet.BalanceSheetResponse> body |> orFail

                // Then: the statement date and every item are present.
                Expect.isTrue
                    (sheet.StatementDate >= before.AddMinutes -1.0
                     && sheet.StatementDate <= DateTime.UtcNow.AddMinutes 1.0)
                    $"the statement date should be the write time, but was %O{sheet.StatementDate}"

                Expect.equal (List.length sheet.Items) 4 "every item should be returned"

                Expect.equal
                    (sheet.Items |> List.map (fun item -> item.Name) |> List.sort)
                    [ "Chequing"; "Credit card"; "House"; "Mortgage" ]
                    "every item should be returned once"

                // Then: four items make each total distinguishable, so a mis-assignment fails.
                Expect.equal sheet.TotalCurrentAssets 2000m "current assets"
                Expect.equal sheet.TotalNonCurrentAssets 400000m "non-current assets"
                Expect.equal sheet.TotalCurrentLiabilities 1500m "current liabilities"
                Expect.equal sheet.TotalNonCurrentLiabilities 300000m "non-current liabilities"
                Expect.equal sheet.TotalAssets 402000m "total assets"
                Expect.equal sheet.TotalLiabilities 301500m "total liabilities"
                Expect.equal sheet.NetWorth 100500m "net worth"
                Expect.equal sheet.WorkingCapital 500m "working capital"

                // Then: money and enums cross the wire as strings.
                Expect.stringContains body "\"totalAssets\":\"" "money should be serialised as a JSON string"
                Expect.stringContains body "\"kind\":\"Asset\"" "kinds should be serialised as strings"
                Expect.stringContains body "\"term\":\"NonCurrent\"" "terms should be serialised as strings"
            }

            testCaseAsync "uniqueness includes the term"
            <| async {
                use app = newApp ()

                // Given: an existing item.
                let! existing = createItem app.Client (request "Chequing" "Asset" "Current" 2000m)

                // When: an identical item is created.
                let! duplicate =
                    TestHttp.postJson app.Client CreateBalanceSheetItem.Path (request "Chequing" "Asset" "Current" 999m)
                    |> Async.AwaitTask

                // Then: the conflict is reported as a validation failure, not a 500.
                Expect.equal duplicate.StatusCode HttpStatusCode.BadRequest "an identical item should be rejected"

                // When: the same name is used with a different term.
                let! otherTerm =
                    TestHttp.postJson
                        app.Client
                        CreateBalanceSheetItem.Path
                        (request "Chequing" "Asset" "NonCurrent" 999m)
                    |> Async.AwaitTask

                // Then: it is a different item.
                Expect.equal otherTerm.StatusCode HttpStatusCode.Created "the term is part of the uniqueness key"

                // When: an update moves an item onto another item's key.
                let! collision =
                    TestHttp.putJson
                        app.Client
                        (routefPath UpdateBalanceSheetItem.Path existing)
                        (request "Chequing" "Asset" "NonCurrent" 1m)
                    |> Async.AwaitTask

                Expect.equal
                    collision.StatusCode
                    HttpStatusCode.BadRequest
                    "an update onto another item's key should be rejected"

                // When: an update keeps its own key.
                let! self =
                    TestHttp.putJson
                        app.Client
                        (routefPath UpdateBalanceSheetItem.Path existing)
                        (request "Chequing" "Asset" "Current" 2500m)
                    |> Async.AwaitTask

                Expect.equal self.StatusCode HttpStatusCode.OK "an update onto itself should be accepted"
            }

            testCaseAsync "deleting the last item leaves the sheet in place"
            <| async {
                use app = newApp ()

                // Given: a sheet with a single item.
                let! id = createItem app.Client (request "Chequing" "Asset" "Current" 2000m)

                // When: the item is deleted.
                let! deleted = deleteItem app.Client id
                Expect.equal deleted HttpStatusCode.NoContent "delete should return 204"

                // Then: the sheet still exists, with zero totals.
                let! sheet = getSheetBody app.Client
                Expect.equal sheet.Items [] "the deleted item should be gone"
                Expect.equal sheet.TotalAssets 0m "an itemless sheet has no assets"
                Expect.equal sheet.NetWorth 0m "an itemless sheet has no net worth"

                // Then: a second delete reports the item is gone.
                let! again = deleteItem app.Client id
                Expect.equal again HttpStatusCode.NotFound "a second delete should return 404"

                let! missing = getItem app.Client id
                Expect.equal missing HttpStatusCode.NotFound "the deleted item should not be readable"
            }

            testCaseAsync "invalid input is reported as a bad request"
            <| async {
                use app = newApp ()

                let post (payload : WriteBalanceSheetItemRequest) =
                    async {
                        let! response =
                            TestHttp.postJson app.Client CreateBalanceSheetItem.Path payload
                            |> Async.AwaitTask

                        return statusOf response
                    }

                // A negative balance (the magnitude is directionless).
                let! negative = post (request "Chequing" "Asset" "Current" -1m)

                Expect.equal negative HttpStatusCode.BadRequest "a negative balance should be rejected"

                // A name longer than the domain maximum.
                let! tooLong = post (request (String.replicate 129 "a") "Asset" "Current" 1m)

                Expect.equal tooLong HttpStatusCode.BadRequest "an over-long name should be rejected"

                // An unrecognised kind.
                let! unknownKind = post (request "Chequing" "Equity" "Current" 1m)

                Expect.equal unknownKind HttpStatusCode.BadRequest "an unknown kind should be rejected"

                // Nothing above was written, so the sheet was never created.
                let! sheet = getSheet app.Client

                Expect.equal sheet.StatusCode HttpStatusCode.NotFound "rejected writes should not create the sheet"
            }

            testCaseAsync "every item write advances the statement date"
            <| async {
                let first = DateTime (2026, 1, 1, 9, 0, 0, DateTimeKind.Utc)
                let second = DateTime (2026, 2, 2, 10, 30, 0, DateTimeKind.Utc)
                let third = DateTime (2026, 3, 3, 11, 45, 0, DateTimeKind.Utc)
                let clock, setTime = testClock (DateTimeOffset first)

                use app =
                    TestApp.create (TestAppConfig.empty |> TestAppConfig.withBalanceSheet clock)

                // Given: the clock starts at the first instant, so the first write is the one
                // that creates the sheet.
                let! id = createItem app.Client (request "Chequing" "Asset" "Current" 2000m)
                let! created = getSheetBody app.Client
                Expect.equal created.StatementDate first "creating the sheet should stamp the write time"

                // When: time moves on and an item is updated.
                setTime (DateTimeOffset second)
                let! updated = updateItem app.Client id (request "Chequing" "Asset" "Current" 2500m)
                Expect.equal updated HttpStatusCode.OK "the update should be accepted"

                let! afterUpdate = getSheetBody app.Client
                Expect.equal afterUpdate.StatementDate second "an update should restamp the statement date"

                // When: time moves on again and the item is deleted.
                setTime (DateTimeOffset third)
                let! deleted = deleteItem app.Client id
                Expect.equal deleted HttpStatusCode.NoContent "the delete should be accepted"

                let! afterDelete = getSheetBody app.Client
                Expect.equal afterDelete.StatementDate third "a delete should restamp the statement date"
            }

            testCaseAsync "the stored statement date is the instant in UTC"
            <| async {
                // A clock in another offset: what it reports as the wall clock and what it means
                // as an instant differ, and only the instant may be stored, because the column
                // carries no offset.
                let elsewhere = TimeSpan.FromHours 13.0
                let wallClock = DateTime (2026, 4, 5, 0, 30, 0)
                let instant = DateTime (2026, 4, 4, 11, 30, 0, DateTimeKind.Utc)
                let clock, _ = testClock (DateTimeOffset (wallClock, elsewhere))

                use app =
                    TestApp.create (TestAppConfig.empty |> TestAppConfig.withBalanceSheet clock)

                let! _ = createItem app.Client (request "Chequing" "Asset" "Current" 2000m)
                let! sheet = getSheetBody app.Client

                Expect.equal
                    sheet.StatementDate
                    instant
                    "the stored date should be the instant in UTC, not the clock's wall clock"
            }
        ]
