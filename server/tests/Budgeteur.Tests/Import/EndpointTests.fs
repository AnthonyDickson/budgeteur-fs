namespace Budgeteur.Tests.Import

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Account
    open Budgeteur.Feature.Import
    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withImports
            |> TestAppConfig.withAccounts Clock.system
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withTags
            |> TestAppConfig.withRules
        )

    let private file name : ImportFileRequest = {
        Name = name
        Content = Fixture.read name
    }

    let private post (client : HttpClient) (files : ImportFileRequest list) =
        TestHttp.postJson client ImportStatements.Path { Files = files }
        |> Async.AwaitTask

    let private import (client : HttpClient) (files : ImportFileRequest list) =
        async {
            let! response = post client files

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "the import should succeed"

            return! TestHttp.readJson<ImportResponse> response
        }

    let private transactions (client : HttpClient) =
        async {
            let! response =
                client.GetAsync ReadAllTransactions.Path |> Async.AwaitTask

            return! TestHttp.readJson<TransactionResponse list> response
        }

    let private accounts (client : HttpClient) =
        async {
            let! response =
                client.GetAsync ReadAllAccounts.Path |> Async.AwaitTask

            return! TestHttp.readJson<AccountResponse list> response
        }

    /// A Kiwibank statement of savings rows, one per day of March.
    let private kiwibank (rows : (int * decimal) list) : ImportFileRequest = {
        Name = "savings.csv"
        Content =
            Formats.kiwibank.Header
            :: (rows
                |> List.map (fun (day, balance) ->
                    $"12-3456-0789012-01,2026-03-%02i{day},2026-03-%02i{day},\
                    INTEREST,INTEREST CREDIT,,,,,,,,,1.00,{balance}"))
            |> String.concat "\n"
    }

    [<Tests>]
    let tests =
        testList "Imports" [
            testCaseAsync "related statements import with transfers and tags"
            <| async {
                use app = newApp ()

                let! dining = Seed.tag app.Client "Dining" "Expense"

                let ruleRequest : CreateRule.CreateRuleRequest = {
                    Pattern = "harbour cafe"
                    TagId = dining
                }

                let! rule =
                    TestHttp.postJson app.Client CreateRule.Path ruleRequest
                    |> Async.AwaitTask

                Expect.equal rule.StatusCode HttpStatusCode.Created "a rule"

                let! result =
                    import app.Client [
                        file "KiwibankChequing.csv"
                        file "KiwibankSavings.csv"
                    ]

                Expect.equal
                    (result.Imported,
                     result.SkippedDuplicates,
                     result.Transfers,
                     result.TaggedByRules)
                    (218, 0, 40, 26)
                    "every row, both sides of each transfer, the rule's matches"

                Expect.equal
                    (result.AccountsCreated
                     |> List.map (fun account -> account.Name, account.Number))
                    [
                        "12-3456-0789012-000", "12-3456-0789012-000"
                        "12-3456-0789012-001", "12-3456-0789012-001"
                    ]
                    "an account per statement, named after its number"

                // Then: transactions carry their account, and transfers have
                // no tag.
                let! all = transactions app.Client

                Expect.equal
                    (all |> List.countBy _.AccountName |> List.sort)
                    [
                        Some "12-3456-0789012-000", 192
                        Some "12-3456-0789012-001", 26
                    ]
                    "each row is in its statement's account"

                Expect.isTrue
                    (all
                     |> List.filter _.IsTransfer
                     |> List.forall (fun transaction -> transaction.Tag = None))
                    "transfers are not tagged"

                // Then: each account's current balance is its statement's
                // closing balance.
                let! accounts = accounts app.Client

                Expect.equal
                    (accounts
                     |> List.map (fun account ->
                         account.Number,
                         account.Balance |> Option.map _.Balance))
                    [
                        Some "12-3456-0789012-000", Some 1053.99m
                        Some "12-3456-0789012-001", Some 5596.99m
                    ]
                    "the balances after the last rows"
            }

            testCaseAsync "a repeated import skips every row"
            <| async {
                use app = newApp ()
                let! _ = import app.Client [ file "KiwibankChequing.csv" ]

                let! again =
                    import app.Client [
                        file "KiwibankChequing.csv"
                        // The same statement twice in one request.
                        file "AsbCard.csv"
                        file "AsbCard.csv"
                    ]

                Expect.equal again.Imported 8 "only the card's rows, once"
                Expect.equal again.SkippedDuplicates 200 "192 + 8 repeated"

                Expect.equal
                    (again.AccountsCreated |> List.map _.Name)
                    [ "XXXX-XXXX-XXXX-0000 (Visa Light)" ]
                    "the card's account is named with its product"

                let! all = transactions app.Client
                Expect.equal (List.length all) 200 "no duplicates were written"
            }

            testCaseAsync "a file that cannot be read fails the whole request"
            <| async {
                use app = newApp ()

                let broken = {
                    Name = "broken.csv"
                    Content =
                        Formats.kiwibank.Header
                        + "\n12-3456-0789012-01,2026-03-01,2026-03-01,X,Y,"
                        + ",,,,,,,,ten,1.00"
                }

                let! response =
                    post app.Client [
                        file "KiwibankChequing.csv"
                        broken
                        {
                            Name = "notes.txt"
                            Content = "hello"
                        }
                    ]

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.BadRequest
                    "the request is rejected"

                let! error = TestHttp.readJson<ApiError> response

                Expect.stringContains
                    error.Details
                    "broken.csv line 2: Amount \"ten\" is not an amount"
                    "the bad row is named"

                Expect.stringContains
                    error.Details
                    "notes.txt: matches no known format"
                    "the unknown file is named"

                let! all = transactions app.Client
                Expect.isEmpty all "nothing from the good file was written"
                let! accounts = accounts app.Client
                Expect.isEmpty accounts "no account was created"
            }

            testCaseAsync
                "an older statement does not change the current balance"
            <| async {
                use app = newApp ()
                let! _ = import app.Client [ kiwibank [ 10, 100m; 11, 101m ] ]
                let! _ = import app.Client [ kiwibank [ 1, 50m; 2, 51m ] ]

                let! accounts = accounts app.Client

                Expect.equal
                    (accounts |> List.map _.Balance)
                    [
                        Some {
                            Balance = 101m
                            AsOf = DateOnly (2026, 3, 11)
                        }
                    ]
                    "the newest observation stays current"
            }

            testCaseAsync "an existing account is found by its number"
            <| async {
                use app = newApp ()

                let! created =
                    TestHttp.postJson app.Client CreateAccount.Path {
                        Name = "Everyday"
                        Number = Some "12-3456-789012-00"
                        Term = "Current"
                        Balance = None
                    }
                    |> Async.AwaitTask

                let! everyday = TestHttp.readJson<AccountResponse> created
                let! result = import app.Client [ file "KiwibankChequing.csv" ]

                Expect.isEmpty result.AccountsCreated "no account is created"

                let! all = transactions app.Client

                Expect.isTrue
                    (all
                     |> List.forall (fun transaction ->
                         transaction.AccountId = Some everyday.Id))
                    "the rows join the existing account"
            }

            testCaseAsync "an import is scoped to the caller"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"
                let! _ = import app.Client [ file "KiwibankSavings.csv" ]

                // Another user's hashes and accounts do not count.
                let! result = import otherUser [ file "KiwibankSavings.csv" ]

                Expect.equal result.Imported 26 "nothing is a duplicate"
                Expect.equal result.Transfers 0 "chequing is not their account"

                Expect.equal
                    (List.length result.AccountsCreated)
                    1
                    "they get their own account"

                let! mine = transactions app.Client
                Expect.equal (List.length mine) 26 "the first user still has 26"
            }
        ]
