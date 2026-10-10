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

    let private createUntaggedWith
        (client : HttpClient)
        (isTransfer : bool)
        description
        =
        async {
            let request : CreateTransaction.CreateTransactionRequest = {
                Amount = -42.50m
                Description = description
                Date = DateOnly (2026, 10, 1)
                IsTransfer = isTransfer
                TagId = None
                AccountId = None
            }

            let! response =
                TestHttp.postJson client CreateTransaction.Path request
                |> Async.AwaitTask

            let! created = TestHttp.readJson<TransactionResponse> response
            return created.Id
        }

    let private createUntagged (client : HttpClient) description =
        createUntaggedWith client false description

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
                let! id = createUntaggedWith app.Client true "To savings"

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
