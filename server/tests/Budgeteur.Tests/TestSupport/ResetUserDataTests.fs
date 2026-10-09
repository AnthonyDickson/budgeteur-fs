namespace Budgeteur.Tests.TestSupport

module ResetUserDataTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.BalanceSheet
    open Budgeteur.Feature.TestSupport
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withBalanceSheet Clock.system
            |> TestAppConfig.withResetUserData
        )

    let private transaction : CreateTransaction.CreateTransactionRequest = {
        Amount = 12.34m
        Description = "Coffee"
        Date = DateOnly (2026, 3, 8)
        IsTransfer = false
        TagId = None
        AccountId = None
    }

    let private item : WriteBalanceSheetItemRequest = {
        Name = "Chequing"
        Kind = "Asset"
        Term = "Current"
        Balance = 2000m
    }

    /// Give a user a transaction, a balance sheet, and a balance sheet item.
    let private seed (client : HttpClient) =
        async {
            let! created = TestHttp.postJson client CreateTransaction.Path transaction |> Async.AwaitTask
            Expect.equal created.StatusCode HttpStatusCode.Created "seeding a transaction should return 201"

            let! created = TestHttp.postJson client CreateBalanceSheetItem.Path item |> Async.AwaitTask
            Expect.equal created.StatusCode HttpStatusCode.Created "seeding an item should return 201"
        }

    let private transactionCount (client : HttpClient) =
        async {
            let! response = client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

            match Decode.fromStringAuto<TransactionResponse list> body with
            | Ok transactions -> return List.length transactions
            | Error error -> return failtest error
        }

    let private sheetStatus (client : HttpClient) =
        async {
            let! response = client.GetAsync ReadBalanceSheet.Path |> Async.AwaitTask
            return response.StatusCode
        }

    [<Tests>]
    let tests =
        testList "ResetUserData" [
            testCaseAsync "clears the current user's data and leaves other users' data"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"
                do! seed app.Client
                do! seed otherUser

                let! response = app.Client.DeleteAsync ResetUserData.Path |> Async.AwaitTask
                Expect.equal response.StatusCode HttpStatusCode.NoContent "reset should return 204"

                let! count = transactionCount app.Client
                Expect.equal count 0 "the user's transactions should be deleted"
                let! status = sheetStatus app.Client
                Expect.equal status HttpStatusCode.NotFound "the user's balance sheet should be deleted"

                let! count = transactionCount otherUser
                Expect.equal count 1 "another user's transactions should remain"
                let! status = sheetStatus otherUser
                Expect.equal status HttpStatusCode.OK "another user's balance sheet should remain"
            }
        ]
