namespace Budgeteur.Tests.Account

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Account
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    /// The server's clock in these tests: 8 March 2026, so the latest accepted
    /// as-of date is the 9th.
    let private clock : Clock =
        fun () -> DateTimeOffset (2026, 3, 8, 12, 0, 0, TimeSpan.Zero)

    let private request (name : string) (number : string option) =
        {
            Name = name
            Number = number
            Term = "Current"
            Balance = None
        }
        : WriteAccountRequest

    let private balance (day : int) (amount : decimal) =
        Some {
            Balance = amount
            AsOf = DateOnly (2026, 3, day)
        }

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withAccounts clock
            |> TestAppConfig.withTransactions
        )

    let private create (client : HttpClient) (payload : WriteAccountRequest) =
        async {
            let! response =
                TestHttp.postJson client CreateAccount.Path payload
                |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.Created
                "create should return 201"

            return! TestHttp.readJson<AccountResponse> response
        }

    let private update
        (client : HttpClient)
        (id : Guid)
        (payload : WriteAccountRequest)
        =
        TestHttp.putJson
            client
            (TestHttp.itemPath UpdateAccount.Path id)
            payload
        |> Async.AwaitTask

    let private read (client : HttpClient) (id : Guid) =
        async {
            let! response =
                client.GetAsync (TestHttp.itemPath ReadAccount.Path id)
                |> Async.AwaitTask

            return! TestHttp.readJson<AccountResponse> response
        }

    [<Tests>]
    let tests =
        testList "Accounts" [
            testCaseAsync "a created account is read back in canonical form"
            <| async {
                use app = newApp ()

                let! created =
                    create app.Client {
                        request "  Everyday  " (Some "12-3456-789012-00") with
                            Balance = balance 8 -12.345m
                    }

                Expect.equal created.Name "Everyday" "the name is trimmed"

                Expect.equal
                    created.Number
                    (Some "12-3456-0789012-000")
                    "the number is stored in canonical form"

                Expect.equal
                    created.Balance
                    (Some {
                        Balance = -12.35m
                        AsOf = DateOnly (2026, 3, 8)
                    })
                    "the balance is signed and rounded to cents"

                let! all =
                    app.Client.GetAsync ReadAllAccounts.Path |> Async.AwaitTask

                let! all = TestHttp.readJson<AccountResponse list> all
                Expect.equal all [ created ] "the list holds the account"

                // An account without a number or a balance is allowed: the
                // balance is unknown, not zero.
                let! bare = create app.Client (request "Cash" (Some "  "))
                Expect.isNone bare.Number "a blank number is no number"
                Expect.isNone bare.Balance "the balance is unknown"
            }

            testCaseAsync "the latest balance is current"
            <| async {
                use app = newApp ()

                let! created =
                    create app.Client {
                        request "Savings" None with
                            Balance = balance 5 100m
                    }

                let enter day amount =
                    update app.Client created.Id {
                        request "Savings" None with
                            Balance = balance day amount
                    }

                // When: a balance on the same date is entered.
                let! _ = enter 5 120m
                let! account = read app.Client created.Id

                Expect.equal
                    account.Balance
                    (Some {
                        Balance = 120m
                        AsOf = DateOnly (2026, 3, 5)
                    })
                    "a balance on the same date replaces it"

                // When: an older balance is entered.
                let! _ = enter 1 50m
                let! account = read app.Client created.Id

                Expect.equal
                    (account.Balance |> Option.map _.Balance)
                    (Some 120m)
                    "an older balance does not replace a newer one"

                // When: an update carries no balance.
                let! _ = update app.Client created.Id (request "Renamed" None)
                let! account = read app.Client created.Id
                Expect.equal account.Name "Renamed" "the name changes"

                Expect.equal
                    (account.Balance |> Option.map _.Balance)
                    (Some 120m)
                    "the balance is kept"

                // When: a balance is dated after tomorrow.
                let! future = enter 10 1m

                Expect.equal
                    future.StatusCode
                    HttpStatusCode.BadRequest
                    "a future balance is rejected"
            }

            testCaseAsync "numbers are unique per user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! existing =
                    create
                        app.Client
                        (request "Everyday" (Some "12-3456-0789012-00"))

                // The same account written another way is a duplicate.
                let! duplicate =
                    TestHttp.postJson
                        app.Client
                        CreateAccount.Path
                        (request "Copy" (Some "12-3456-0789012-000"))
                    |> Async.AwaitTask

                Expect.equal
                    duplicate.StatusCode
                    HttpStatusCode.BadRequest
                    "a duplicate number is rejected"

                let! own =
                    update
                        app.Client
                        existing.Id
                        (request "Everyday" (Some "12-3456-0789012-00"))

                Expect.equal
                    own.StatusCode
                    HttpStatusCode.OK
                    "an account keeps its own number"

                let! _ =
                    create
                        otherUser
                        (request "Mine" (Some "12-3456-0789012-00"))

                let! _ = create app.Client (request "Cash" None)
                let! _ = create app.Client (request "Wallet" None)

                let! invalid =
                    TestHttp.postJson
                        app.Client
                        CreateAccount.Path
                        (request "Bad" (Some "not a number"))
                    |> Async.AwaitTask

                Expect.equal
                    invalid.StatusCode
                    HttpStatusCode.BadRequest
                    "an invalid number is rejected"
            }

            testCaseAsync "an account is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"
                let! created = create app.Client (request "Everyday" None)

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllAccounts.Path
                        (TestHttp.itemPath ReadAccount.Path created.Id)
                        (request "Hijacked" None)
            }

            testCaseAsync "deleting an account deletes its transactions"
            <| async {
                use app = newApp ()
                let! account = create app.Client (request "Everyday" None)

                let transaction
                    accountId
                    : CreateTransaction.CreateTransactionRequest = {
                    Amount = -12.50m
                    Description = "Coffee"
                    Date = DateOnly (2026, 3, 8)
                    IsTransfer = false
                    TagId = None
                    AccountId = accountId
                }

                let! inAccount =
                    TestHttp.postJson
                        app.Client
                        CreateTransaction.Path
                        (transaction (Some account.Id))
                    |> Async.AwaitTask

                let! inAccount =
                    TestHttp.readJson<TransactionResponse> inAccount

                let! elsewhere =
                    TestHttp.postJson
                        app.Client
                        CreateTransaction.Path
                        (transaction None)
                    |> Async.AwaitTask

                let! elsewhere =
                    TestHttp.readJson<TransactionResponse> elsewhere

                let! deleted =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath DeleteAccount.Path account.Id
                    )
                    |> Async.AwaitTask

                Expect.equal
                    deleted.StatusCode
                    HttpStatusCode.NoContent
                    "delete should return 204"

                let! all =
                    app.Client.GetAsync ReadAllTransactions.Path
                    |> Async.AwaitTask

                let! all = TestHttp.readJson<TransactionResponse list> all

                Expect.equal
                    (all |> List.map _.Id)
                    [ elsewhere.Id ]
                    "only the account's transactions are deleted"

                Expect.notEqual inAccount.Id elsewhere.Id "two transactions"

                let! again =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath DeleteAccount.Path account.Id
                    )
                    |> Async.AwaitTask

                Expect.equal
                    again.StatusCode
                    HttpStatusCode.NotFound
                    "a second delete should return 404"
            }
        ]
