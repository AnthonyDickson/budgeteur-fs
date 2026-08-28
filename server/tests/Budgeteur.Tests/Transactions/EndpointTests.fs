namespace Budgeteur.Tests.Transactions

module EndpointTests =
    open System
    open System.Net
    open Expecto

    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    /// Fill the Oxpecker routef `{%O:guid}` placeholder in an item path with a concrete id.
    let private routefPath (path : string) (id : Guid) =
        path.Replace ("{%O:guid}", id.ToString ())

    /// A valid create request payload. No id is supplied, matching the server-owned-id contract.
    let private request (description : string) (amount : decimal) : CreateTransaction.CreateTransactionRequest = {
        Amount = amount
        Description = description
        // Aligned to whole seconds, matching the epoch-second precision used for storage.
        Date = DateOnly (2026, 3, 8)
        IsTransfer = false
        TagId = None
        AccountId = None
    }

    let newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTransactions)

    [<Tests>]
    let tests =
        testList "Transactions" [
            testCaseAsync "GET /api/transactions returns empty list when no transactions exist"
            <| async {
                use app = newApp ()

                let! response = app.Client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
                let result = Decode.fromStringAuto<Transaction list> body

                Expect.equal result (Ok []) "body should be empty list"
            }

            testCaseAsync "GET /api/transactions returns seeded transactions"
            <| async {
                use app = newApp ()

                let input = request "Groceries" 42.50m
                let! _ = TestHttp.postJson app.Client CreateTransaction.Path input |> Async.AwaitTask

                let! response = app.Client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromStringAuto<TransactionResponse list> body with
                | Ok [ item ] ->
                    Expect.equal input.Description item.Description "description should match"
                    Expect.equal input.Amount item.Amount "amount should match"
                    Expect.equal input.Date item.Date "date should match"
                | _ -> failtest "Expected one transaction"
            }

            testCaseAsync "GET /api/transactions/{id} returns the transaction"
            <| async {
                use app = newApp ()

                let input = request "Salary" 2500.00m
                let! createResponse = TestHttp.postJson app.Client CreateTransaction.Path input |> Async.AwaitTask

                let! createBody = createResponse.Content.ReadAsStringAsync () |> Async.AwaitTask

                let id =
                    match Decode.fromStringAuto<TransactionResponse> createBody with
                    | Ok created -> created.Id
                    | Error err -> failtest err

                let! response = app.Client.GetAsync (routefPath ReadTransaction.Path id) |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromStringAuto<TransactionResponse> body with
                | Ok item ->
                    Expect.equal input.Description item.Description "description should match"
                    Expect.equal input.Amount item.Amount "amount should match"
                | Error err -> failtest err
            }

            testCaseAsync "GET /api/transactions/{id} returns 404 for missing transaction"
            <| async {
                use app = newApp ()

                let! response =
                    app.Client.GetAsync (routefPath ReadTransaction.Path (Guid.CreateVersion7 ()))
                    |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.NotFound "status code should be 404"
            }

            testCaseAsync "POST /api/transactions creates a transaction"
            <| async {
                use app = newApp ()

                let input = request "Utilities" 99.99m

                let! response = TestHttp.postJson app.Client CreateTransaction.Path input |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.Created "status code should be 201"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromStringAuto<TransactionResponse> body with
                | Ok created ->
                    Expect.equal input.Description created.Description "description should match"
                    Expect.equal input.Amount created.Amount "amount should match"
                    Expect.equal input.Date created.Date "date should match"
                | Error err -> failtest err
            }

            testCaseAsync "POST /api/transactions trims and stores the description"
            <| async {
                use app = newApp ()

                let input = {
                    request "Rent" 1200.00m with
                        Description = "  Rent  "
                }

                let! response = TestHttp.postJson app.Client CreateTransaction.Path input |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.Created "status code should be 201"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromStringAuto<TransactionResponse> body with
                | Ok created -> Expect.equal created.Description "Rent" "description should be trimmed"
                | Error err -> failtest err
            }

            testCaseAsync "PUT /api/transactions/{id} updates a transaction"
            <| async {
                use app = newApp ()

                // Given: an existing transaction.
                let original = request "Old description" 12.50m
                let! _ = TestHttp.postJson app.Client CreateTransaction.Path original |> Async.AwaitTask

                // Given: its id, recovered from the store.
                let! body = app.Client.GetStringAsync ReadAllTransactions.Path |> Async.AwaitTask

                let id =
                    match Decode.fromStringAuto<TransactionResponse list> body with
                    | Ok [ item ] -> item.Id
                    | _ -> failtest "Expected one transaction"

                // When: the transaction is updated with new fields.
                let update = request "New description" 13.37m

                let! response =
                    TestHttp.putJson app.Client (routefPath UpdateTransaction.Path id) update
                    |> Async.AwaitTask

                // Then: the updated transaction is returned.
                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromStringAuto<TransactionResponse> body with
                | Ok updated ->
                    Expect.equal id updated.Id "id should match the URL id"
                    Expect.equal update.Description updated.Description "description should match"
                    Expect.equal update.Amount updated.Amount "amount should match"
                | Error err -> failtest err
            }

            testCaseAsync "DELETE /api/transactions/{id} removes the transaction"
            <| async {
                use app = newApp ()

                // Given: an existing transaction, its id recovered from the store.
                let! _ =
                    TestHttp.postJson app.Client CreateTransaction.Path (request "To delete" 15.00m)
                    |> Async.AwaitTask

                let! body = app.Client.GetStringAsync ReadAllTransactions.Path |> Async.AwaitTask

                let id =
                    match Decode.fromStringAuto<TransactionResponse list> body with
                    | Ok [ item ] -> item.Id
                    | _ -> failtest "Expected one transaction"

                // When: the transaction is deleted.
                let! deleteResponse = app.Client.DeleteAsync (routefPath DeleteTransaction.Path id) |> Async.AwaitTask

                // Then: deletion succeeds.
                Expect.equal deleteResponse.StatusCode HttpStatusCode.NoContent "delete status should be 204"

                // Then: the transaction is no longer retrievable.
                let! getResponse = app.Client.GetAsync (routefPath ReadTransaction.Path id) |> Async.AwaitTask

                Expect.equal getResponse.StatusCode HttpStatusCode.NotFound "get after delete should be 404"
            }
        ]
