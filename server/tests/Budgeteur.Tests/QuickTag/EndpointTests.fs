namespace Budgeteur.Tests.QuickTag

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.AutoTag
    open Budgeteur.Feature.QuickTag
    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Transaction
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withQuickTag
            |> TestAppConfig.withAutoTag
            |> TestAppConfig.withRules
            |> TestAppConfig.withTags
            |> TestAppConfig.withTransactions
        )

    let private createRule (client : HttpClient) pattern tagId =
        async {
            let request : CreateRule.CreateRuleRequest = {
                Pattern = pattern
                TagId = tagId
            }

            let! response =
                TestHttp.postJson client CreateRule.Path request
                |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.Created
                "creating a rule should return 201"
        }

    let private untagged
        description
        : CreateTransaction.CreateTransactionRequest = {
        Amount = -42.50m
        Description = description
        Date = DateOnly (2026, 10, 1)
        IsTransfer = false
        TagId = None
        AccountId = None
    }

    let private create
        (client : HttpClient)
        (request : CreateTransaction.CreateTransactionRequest)
        =
        async {
            let! response =
                TestHttp.postJson client CreateTransaction.Path request
                |> Async.AwaitTask

            let! created = TestHttp.readJson<TransactionResponse> response
            return created.Id
        }

    let private quickTag (client : HttpClient) (id : Guid) (tagId : Guid) =
        TestHttp.putJson
            client
            (TestHttp.itemPath QuickTagTransaction.Path id)
            ({ TagId = tagId } : QuickTagTransaction.QuickTagRequest)
        |> Async.AwaitTask

    let private dismiss (client : HttpClient) (id : Guid) =
        client.DeleteAsync (TestHttp.itemPath DismissTransaction.Path id)
        |> Async.AwaitTask

    let private expectStatus
        (expected : HttpStatusCode)
        (message : string)
        (response : HttpResponseMessage)
        =
        Expect.equal response.StatusCode expected message

    let private readTag (client : HttpClient) (id : Guid) =
        async {
            let! response =
                client.GetAsync (TestHttp.itemPath ReadTransaction.Path id)
                |> Async.AwaitTask

            let! transaction = TestHttp.readJson<TransactionResponse> response
            return transaction.Tag
        }

    let private readQueue (client : HttpClient) =
        async {
            let! response = client.GetAsync ReadQueue.Path |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "reading the queue should return 200"

            return! TestHttp.readJson<QueueResponse> response
        }

    let private onDate description (date : DateOnly) = {
        untagged description with
            Date = date
    }

    /// <summary>How many transactions "Tag untagged" tags. A dismissed
    /// transaction has no tag but is not untagged, so a run skips it.</summary>
    let private tagUntagged (client : HttpClient) =
        async {
            let! response =
                TestHttp.postJson client RunAutoTag.Path {
                    Action = "TagUntagged"
                }
                |> Async.AwaitTask

            let! counts = TestHttp.readJson<RunAutoTagResponse> response
            return counts.Tagged
        }

    [<Tests>]
    let tests =
        testList "QuickTag" [
            testCaseAsync
                "quick tagging sets a manual tag, replacing a dismissal"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                let! id = create app.Client (untagged "Countdown")

                let! response = quickTag app.Client id groceries
                expectStatus HttpStatusCode.NoContent "tagging is 204" response

                let! response = quickTag app.Client id groceries

                expectStatus
                    HttpStatusCode.NoContent
                    "repeating is 204"
                    response

                let! tag = readTag app.Client id

                Expect.equal
                    tag
                    (Some { Id = groceries; Source = "Manual" })
                    "the tag should be manual"

                let! response = dismiss app.Client id

                expectStatus
                    HttpStatusCode.NoContent
                    "dismissing is 204"
                    response

                let! tag = readTag app.Client id
                Expect.isNone tag "a dismissed transaction has no tag"

                let! _ = quickTag app.Client id groceries
                let! tag = readTag app.Client id

                Expect.equal
                    tag
                    (Some { Id = groceries; Source = "Manual" })
                    "a tag should replace the dismissal"
            }

            testCaseAsync "rules never tag a dismissed transaction"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                do! createRule app.Client "COUNTDOWN" groceries
                let! id = create app.Client (untagged "Countdown")

                let! response = dismiss app.Client id

                expectStatus
                    HttpStatusCode.NoContent
                    "dismissing is 204"
                    response

                let! response = dismiss app.Client id

                expectStatus
                    HttpStatusCode.NoContent
                    "repeating is 204"
                    response

                let! tagged = tagUntagged app.Client
                Expect.equal tagged 0 "tag untagged should skip the dismissal"
                let! tag = readTag app.Client id
                Expect.isNone tag "the transaction should stay without a tag"
            }

            testCaseAsync "another user's transaction is not found"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                do! createRule app.Client "COUNTDOWN" groceries
                let! id = create app.Client (untagged "Countdown")

                let other = app.ClientForUser "other-user"
                let! otherTag = Seed.tag other "Dining" "Expense"

                let! response = quickTag other id otherTag
                expectStatus HttpStatusCode.NotFound "tagging is 404" response

                let! response = dismiss other id

                expectStatus
                    HttpStatusCode.NotFound
                    "dismissing is 404"
                    response

                let! tagged = tagUntagged app.Client
                Expect.equal tagged 1 "the transaction should still be untagged"
            }

            testCaseAsync "a tag the user does not have is rejected"
            <| async {
                use app = newApp ()
                let! id = create app.Client (untagged "Countdown")

                let other = app.ClientForUser "other-user"
                let! otherTag = Seed.tag other "Dining" "Expense"

                let! response = quickTag app.Client id otherTag
                expectStatus HttpStatusCode.BadRequest "another user's" response

                let! response = quickTag app.Client id (Guid.CreateVersion7 ())
                expectStatus HttpStatusCode.BadRequest "missing" response

                let! tag = readTag app.Client id
                Expect.isNone tag "the transaction should stay untagged"
            }

            testCaseAsync "a transfer cannot be tagged or dismissed"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"

                let! id =
                    create app.Client {
                        untagged "To savings" with
                            IsTransfer = true
                    }

                let! response = quickTag app.Client id groceries
                expectStatus HttpStatusCode.BadRequest "tagging is 400" response

                let! response = dismiss app.Client id

                expectStatus
                    HttpStatusCode.BadRequest
                    "dismissing is 400"
                    response
            }

            testCaseAsync
                "the queue is the user's untagged transactions, newest first"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"

                let! older =
                    create app.Client (onDate "Older" (DateOnly (2026, 9, 1)))

                let! newer =
                    create app.Client (onDate "Newer" (DateOnly (2026, 10, 2)))
                // Same date as the next: the later id comes first.
                let! first =
                    create app.Client (onDate "First" (DateOnly (2026, 10, 1)))

                let! second =
                    create app.Client (onDate "Second" (DateOnly (2026, 10, 1)))

                let! _ =
                    create app.Client {
                        untagged "Tagged" with
                            TagId = Some groceries
                    }

                let! dismissed = create app.Client (untagged "Dismissed")
                let! _ = dismiss app.Client dismissed

                let! _ =
                    create app.Client {
                        untagged "Transfer" with
                            IsTransfer = true
                    }

                let other = app.ClientForUser "other-user"
                let! _ = create other (untagged "Another user's")

                let! queue = readQueue app.Client

                Expect.equal
                    (queue.Transactions |> List.map _.Id)
                    [ newer; second; first; older ]
                    "only untagged transactions, newest first"

                Expect.equal queue.Total 4 "the total should count the queue"

                Expect.equal
                    (List.tryHead queue.Transactions)
                    (Some {
                        Id = newer
                        Amount = -42.50m
                        Description = "Newer"
                        Date = DateOnly (2026, 10, 2)
                        AccountName = None
                    })
                    "an entry should carry the transaction's details"
            }

            testCaseAsync
                "a batch holds 50, and the next fetch continues the queue"
            <| async {
                use app = newApp ()

                let! ids =
                    [ 1..51 ]
                    |> List.map (fun day ->
                        create
                            app.Client
                            (onDate
                                $"Transaction {day}"
                                (DateOnly(2026, 1, 1).AddDays day)))
                    |> Async.Sequential

                let! queue = readQueue app.Client
                Expect.hasLength queue.Transactions 50 "a batch holds 50"
                Expect.equal queue.Total 51 "the total counts all 51"

                let oldest = ids[0]

                Expect.isFalse
                    (queue.Transactions |> List.exists (fun t -> t.Id = oldest))
                    "the oldest should wait for the next batch"

                for t in queue.Transactions do
                    let! _ = dismiss app.Client t.Id
                    ()

                let! queue = readQueue app.Client

                Expect.equal
                    (queue.Transactions |> List.map _.Id)
                    [ oldest ]
                    "the next batch should hold the rest"

                Expect.equal queue.Total 1 "the total should shrink"
            }
        ]
