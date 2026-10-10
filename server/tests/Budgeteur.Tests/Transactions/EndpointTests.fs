namespace Budgeteur.Tests.Transactions

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto
    open Microsoft.Data.Sqlite

    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    /// A valid create request payload. No id is supplied, matching the server-owned-id contract.
    let private request (description : string) (amount : decimal) : CreateTransaction.CreateTransactionRequest = {
        Amount = amount
        Description = description
        Date = DateOnly (2026, 3, 8)
        IsTransfer = false
        TagId = None
        AccountId = None
    }

    let newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTransactions)

    /// Create a transaction and return the created representation.
    let private create (client : HttpClient) (input : CreateTransaction.CreateTransactionRequest) =
        async {
            let! response =
                TestHttp.postJson client CreateTransaction.Path input |> Async.AwaitTask

            Expect.equal response.StatusCode HttpStatusCode.Created "create should return 201"
            return! TestHttp.readJson<TransactionResponse> response
        }

    [<Tests>]
    let tests =
        testList "Transactions" [
            testCaseAsync "a created transaction can be read and listed"
            <| async {
                use app = newApp ()

                let! empty = app.Client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask
                let! empty = TestHttp.readJson<TransactionResponse list> empty
                Expect.isEmpty empty "a new user should have no transactions"

                let input = request "Groceries" 42.50m
                let! created = create app.Client input

                Expect.equal
                    (created.Description, created.Amount, created.Date)
                    (input.Description, input.Amount, input.Date)
                    "create should return the stored fields"

                let! read =
                    app.Client.GetAsync (TestHttp.itemPath ReadTransaction.Path created.Id)
                    |> Async.AwaitTask

                Expect.equal read.StatusCode HttpStatusCode.OK "read should return 200"
                let! read = TestHttp.readJson<TransactionResponse> read
                Expect.equal read created "read should return the created transaction"

                let! all = app.Client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask
                let! all = TestHttp.readJson<TransactionResponse list> all
                Expect.equal all [ created ] "the list should hold the created transaction"
            }

            testCaseAsync "POST /api/transactions rejects a date that is not ISO-8601"
            <| async {
                use app = newApp ()

                let json =
                    Encode.toStringAuto (request "Groceries" 42.50m)
                    |> fun json -> json.Replace ("\"2026-03-08\"", "\"03/08/2026\"")

                Expect.stringContains json "03/08/2026" "the payload should carry the non-ISO date"

                let content = new StringContent (json, Text.Encoding.UTF8, "application/json")

                let! response =
                    app.Client.PostAsync (CreateTransaction.Path, content) |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "status code should be 400"
            }

            testCaseAsync "POST /api/transactions trims and stores the description"
            <| async {
                use app = newApp ()

                let! created =
                    create app.Client {
                        request "Rent" 1200.00m with
                            Description = "  Rent  "
                    }

                Expect.equal created.Description "Rent" "description should be trimmed"
            }

            testCaseAsync "PUT /api/transactions/{id} updates a transaction"
            <| async {
                use app = newApp ()

                // Given: an existing transaction.
                let! original = create app.Client (request "Old description" 12.50m)

                // When: the transaction is updated with new fields.
                let update = request "New description" 13.37m

                let! response =
                    TestHttp.putJson app.Client (TestHttp.itemPath UpdateTransaction.Path original.Id) update
                    |> Async.AwaitTask

                // Then: the updated transaction is returned.
                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"
                let! updated = TestHttp.readJson<TransactionResponse> response
                Expect.equal original.Id updated.Id "id should match the URL id"
                Expect.equal update.Description updated.Description "description should match"
                Expect.equal update.Amount updated.Amount "amount should match"
            }

            testCaseAsync "PUT /api/transactions/{id} keeps the import hash"
            <| async {
                use app = newApp ()

                // Given: an imported transaction. Imports do not exist yet, so the hash is set directly.
                let! created = create app.Client (request "Imported" 12.50m)

                let importHash () =
                    use conn = new SqliteConnection (app.ConnectionString)
                    conn.Open ()
                    use cmd = conn.CreateCommand ()
                    cmd.CommandText <- "SELECT ImportHash FROM Transactions"
                    cmd.ExecuteScalar ()

                do
                    use conn = new SqliteConnection (app.ConnectionString)
                    conn.Open ()
                    use cmd = conn.CreateCommand ()
                    cmd.CommandText <- "UPDATE Transactions SET ImportHash = 'row-hash'"
                    cmd.ExecuteNonQuery () |> ignore

                // When: the user edits it, e.g. to tag it.
                let! response =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateTransaction.Path created.Id)
                        (request "Edited" 12.50m)
                    |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                // Then: the hash survives, so a re-import still recognises the transaction.
                Expect.equal (importHash ()) (box "row-hash") "the import hash should be unchanged"
            }

            testCaseAsync "a transaction is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! created = create app.Client (request "Salary" 2500.00m)

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllTransactions.Path
                        (TestHttp.itemPath ReadTransaction.Path created.Id)
                        (request "Hijacked" 1.00m)
            }

            testCaseAsync "a transaction cannot use another user's tag"
            <| async {
                use app =
                    TestApp.create (TestAppConfig.empty |> TestAppConfig.withTransactions |> TestAppConfig.withTags)

                use otherUser = app.ClientForUser "other-user"

                let! tagId = Seed.tag app.Client "Salary" "Income"

                let! response =
                    TestHttp.postJson otherUser CreateTransaction.Path {
                        request "Salary" 2500.00m with
                            TagId = Some tagId
                    }
                    |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "another user's tag should be rejected"
            }

            testCaseAsync "DELETE /api/transactions/{id} removes the transaction"
            <| async {
                use app = newApp ()

                // Given: an existing transaction.
                let! created = create app.Client (request "To delete" 15.00m)

                // When: the transaction is deleted.
                let! deleteResponse =
                    app.Client.DeleteAsync (TestHttp.itemPath DeleteTransaction.Path created.Id)
                    |> Async.AwaitTask

                // Then: deletion succeeds.
                Expect.equal deleteResponse.StatusCode HttpStatusCode.NoContent "delete status should be 204"

                // Then: the transaction is no longer retrievable.
                let! getResponse =
                    app.Client.GetAsync (TestHttp.itemPath ReadTransaction.Path created.Id)
                    |> Async.AwaitTask

                Expect.equal getResponse.StatusCode HttpStatusCode.NotFound "get after delete should be 404"
            }
        ]
