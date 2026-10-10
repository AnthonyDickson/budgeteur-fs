namespace Budgeteur.Tests.AutoTag

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.AutoTag
    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Transaction
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
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

    let private createUntagged (client : HttpClient) description =
        create client (untagged description)

    let private run (client : HttpClient) (action : string) =
        TestHttp.postJson client RunAutoTag.Path { Action = action }
        |> Async.AwaitTask

    let private runOk (client : HttpClient) (action : string) =
        async {
            let! response = run client action

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "a run should return 200"

            return! TestHttp.readJson<RunAutoTagResponse> response
        }

    let private readMatches (client : HttpClient) (query : string) =
        client.GetAsync (ReadMatches.Path + query) |> Async.AwaitTask

    let private readTag (client : HttpClient) (id : Guid) =
        async {
            let! response =
                client.GetAsync (TestHttp.itemPath ReadTransaction.Path id)
                |> Async.AwaitTask

            let! transaction = TestHttp.readJson<TransactionResponse> response
            return transaction.Tag
        }

    [<Tests>]
    let tests =
        testList "AutoTag" [
            testCaseAsync "TagUntagged gives a matching transaction a rule tag"
            <| async {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                do! createRule app.Client "COUNTDOWN" groceries
                let! id = createUntagged app.Client "PAY Countdown Ponsonby"

                let! counts = runOk app.Client "TagUntagged"

                Expect.equal
                    counts
                    { Tagged = 1; Changed = 0; Cleared = 0 }
                    "one transaction should be tagged"

                let! tag = readTag app.Client id

                Expect.equal
                    tag
                    (Some { Id = groceries; Source = "Rule" })
                    "the transaction should have the rule's tag"
            }

            testCaseAsync "a run leaves transfers untagged"
            <| async {
                use app = newApp ()
                let! savings = Seed.tag app.Client "Savings" "Expense"
                do! createRule app.Client "SAVINGS" savings

                let! id =
                    create app.Client {
                        untagged "To savings" with
                            IsTransfer = true
                    }

                let! counts = runOk app.Client "Retag"

                Expect.equal
                    counts
                    { Tagged = 0; Changed = 0; Cleared = 0 }
                    "a transfer should not be a candidate"

                let! tag = readTag app.Client id
                Expect.isNone tag "the transfer should stay untagged"
            }

            testCaseAsync "a run reads and writes only the caller's data"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                do! createRule app.Client "COUNTDOWN" groceries
                let! othersId = createUntagged otherUser "Countdown"

                let! ownRun = runOk app.Client "Retag"
                let! othersRun = runOk otherUser "Retag"

                let none : RunAutoTagResponse = {
                    Tagged = 0
                    Changed = 0
                    Cleared = 0
                }

                Expect.equal ownRun none "the caller has no transactions"

                Expect.equal
                    othersRun
                    none
                    "another user's rules should not apply"

                let! tag = readTag otherUser othersId
                Expect.isNone tag "another user's transaction stays untagged"
            }

            testCaseAsync
                "matches counts the caller's transactions, not transfers"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let on day description = {
                    untagged description with
                        Date = DateOnly (2026, 10, day)
                }

                let! _ = create app.Client (on 1 "Countdown Ponsonby")
                let! _ = create app.Client (on 3 "Countdown Grey Lynn")
                let! _ = create app.Client (on 2 "Countdown Ponsonby")
                let! _ = create app.Client (on 4 "Rent")

                let! _ =
                    create app.Client {
                        on 5 "Countdown savings" with
                            IsTransfer = true
                    }

                let! _ = create otherUser (on 6 "Countdown")

                let! response = readMatches app.Client "?pattern=countdown"

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.OK
                    "matches should return 200"

                let! matches = TestHttp.readJson<MatchesResponse> response

                Expect.equal
                    matches
                    {
                        Count = 3
                        Samples = [
                            "Countdown Grey Lynn"
                            "Countdown Ponsonby"
                        ]
                    }
                    "the most recent distinct descriptions should be sampled"
            }

            testCaseAsync "matches rejects a missing or blank pattern"
            <| async {
                use app = newApp ()

                for query in [ ""; "?pattern=%20" ] do
                    let! response = readMatches app.Client query

                    Expect.equal
                        response.StatusCode
                        HttpStatusCode.BadRequest
                        $"the query '{query}' should be rejected"
            }

            testCaseAsync "an unknown action is a bad request"
            <| async {
                use app = newApp ()
                let! response = run app.Client "TagEverything"

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.BadRequest
                    "the action should be rejected"
            }
        ]
