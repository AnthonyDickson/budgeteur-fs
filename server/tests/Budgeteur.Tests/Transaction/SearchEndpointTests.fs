namespace Budgeteur.Tests.Transaction

module SearchEndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.QuickTag
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.Clock
    open Budgeteur.Tests

    let private clock : Clock =
        fun () -> DateTimeOffset (2026, 10, 14, 0, 0, 0, TimeSpan.Zero)

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withTransactions
            |> TestAppConfig.withTags
            |> TestAppConfig.withAccounts clock
            |> TestAppConfig.withQuickTag
        )

    let private anyCriteria : SearchCriteriaRequest = {
        Text = ""
        Dates = {
            Preset = "AnyTime"
            From = None
            To = None
        }
        Account = { State = "Any"; Id = None }
        Tag = { State = "Any"; Id = None }
        Amount = {
            Direction = "Any"
            Minimum = None
            Maximum = None
        }
    }

    let private march (day : int) = DateOnly (2026, 3, day)

    let private february (day : int) = Some (DateOnly (2026, 2, day))

    let private transaction (description : string) (amount : decimal) =
        ({
            Amount = amount
            Description = description
            Date = march 8
            IsTransfer = false
            TagId = None
            AccountId = None
        }
        : CreateTransaction.CreateTransactionRequest)

    /// <summary>Create a transaction and return its id.</summary>
    let private create
        (client : HttpClient)
        (request : CreateTransaction.CreateTransactionRequest)
        =
        async {
            let! response =
                TestHttp.postJson client CreateTransaction.Path request
                |> Async.AwaitTask

            Expect.equal
                response.StatusCode
                HttpStatusCode.Created
                "create should return 201"

            let! created = TestHttp.readJson<TransactionResponse> response
            return created.Id
        }

    let private post
        (client : HttpClient)
        (criteria : SearchCriteriaRequest)
        (cursor : string option)
        =
        let request : SearchRequest = {
            Criteria = criteria
            Today = march 15
            Cursor = cursor
        }

        TestHttp.postJson client SearchTransactions.Path request
        |> Async.AwaitTask

    let private searchPage
        (client : HttpClient)
        (criteria : SearchCriteriaRequest)
        (cursor : string option)
        =
        async {
            let! response = post client criteria cursor

            Expect.equal
                response.StatusCode
                HttpStatusCode.OK
                "search should return 200"

            return! TestHttp.readJson<SearchResponse> response
        }

    /// <summary>The descriptions of the first page's matches, in
    /// order.</summary>
    let private search
        (client : HttpClient)
        (criteria : SearchCriteriaRequest)
        =
        async {
            let! page = searchPage client criteria None

            return
                page.Transactions
                |> List.map (fun transaction -> transaction.Description)
        }

    /// <summary>The descriptions of the first page's matches, sorted, for
    /// matches on the same date.</summary>
    let private searchSorted
        (client : HttpClient)
        (criteria : SearchCriteriaRequest)
        =
        async {
            let! matches = search client criteria
            return List.sort matches
        }

    let private amount
        (direction : string)
        (minimum : decimal option)
        (maximum : decimal option)
        = {
        anyCriteria with
            Amount = {
                Direction = direction
                Minimum = minimum
                Maximum = maximum
            }
    }

    [<Tests>]
    let tests =
        testList "Transaction search endpoint" [
            testAsync "text matches descriptions ignoring case" {
                use app = newApp ()

                for description in
                    [ "COUNTDOWN AUCKLAND"; "New World"; "countdown metro" ] do
                    do!
                        create app.Client (transaction description -1m)
                        |> Async.Ignore

                let! matches =
                    search app.Client { anyCriteria with Text = "Countdown" }

                Expect.equal
                    matches
                    [ "countdown metro"; "COUNTDOWN AUCKLAND" ]
                    "matches, newest first"
            }

            testAsync "dates match inclusive days and presets resolve" {
                use app = newApp ()

                for date in
                    [
                        DateOnly (2026, 1, 31)
                        DateOnly (2026, 2, 1)
                        DateOnly (2026, 2, 28)
                        DateOnly (2026, 3, 1)
                    ] do
                    do!
                        create app.Client {
                            transaction (date.ToString "yyyy-MM-dd") -1m with
                                Date = date
                        }
                        |> Async.Ignore

                let! custom =
                    search app.Client {
                        anyCriteria with
                            Dates = {
                                Preset = "Custom"
                                From = february 1
                                To = february 28
                            }
                    }

                Expect.equal custom [ "2026-02-28"; "2026-02-01" ] "custom"

                let! lastMonth =
                    searchPage
                        app.Client
                        {
                            anyCriteria with
                                Dates = {
                                    Preset = "LastMonth"
                                    From = None
                                    To = None
                                }
                        }
                        None

                Expect.equal
                    (lastMonth.Transactions |> List.map _.Description)
                    [ "2026-02-28"; "2026-02-01" ]
                    "last month from 15 March"

                Expect.equal
                    (lastMonth.From, lastMonth.To)
                    (february 1, february 28)
                    "resolved days"
            }

            testAsync "account matches one account or none" {
                use app = newApp ()
                let! everyday = Seed.account app.Client "Everyday" None
                let! savings = Seed.account app.Client "Savings" None

                do!
                    create app.Client {
                        transaction "Everyday" -1m with
                            AccountId = Some everyday
                    }
                    |> Async.Ignore

                do!
                    create app.Client {
                        transaction "Savings" -1m with
                            AccountId = Some savings
                    }
                    |> Async.Ignore

                do! create app.Client (transaction "Cash" -1m) |> Async.Ignore

                let! oneAccount =
                    search app.Client {
                        anyCriteria with
                            Account = { State = "Account"; Id = Some savings }
                    }

                Expect.equal oneAccount [ "Savings" ] "one account"

                let! noAccount =
                    search app.Client {
                        anyCriteria with
                            Account = { State = "NoAccount"; Id = None }
                    }

                Expect.equal noAccount [ "Cash" ] "no account"
            }

            testAsync "tag matches a tag or a categorisation" {
                use app = newApp ()
                let! groceries = Seed.tag app.Client "Groceries" "Expense"
                let! fuel = Seed.tag app.Client "Fuel" "Expense"

                do!
                    create app.Client {
                        transaction "Groceries" -1m with
                            TagId = Some groceries
                    }
                    |> Async.Ignore

                do!
                    create app.Client {
                        transaction "Fuel" -1m with
                            TagId = Some fuel
                    }
                    |> Async.Ignore

                do!
                    create app.Client (transaction "Untagged" -1m)
                    |> Async.Ignore

                do!
                    create app.Client {
                        transaction "Transfer" -1m with
                            IsTransfer = true
                    }
                    |> Async.Ignore

                let! dismissedId =
                    create app.Client (transaction "Dismissed" -1m)

                let! dismiss =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath DismissTransaction.Path dismissedId
                    )
                    |> Async.AwaitTask

                Expect.isTrue dismiss.IsSuccessStatusCode "dismiss"

                let byTag state id =
                    searchSorted app.Client {
                        anyCriteria with
                            Tag = { State = state; Id = id }
                    }

                let! oneTag = byTag "Tag" (Some fuel)
                Expect.equal oneTag [ "Fuel" ] "one tag"

                let! withoutTag = byTag "WithoutTag" None

                Expect.equal
                    withoutTag
                    [ "Dismissed"; "Untagged" ]
                    "without a tag"

                let! untagged = byTag "Untagged" None
                Expect.equal untagged [ "Untagged" ] "untagged"

                let! dismissed = byTag "Dismissed" None
                Expect.equal dismissed [ "Dismissed" ] "dismissed"

                let! transfer = byTag "Transfer" None
                Expect.equal transfer [ "Transfer" ] "transfer"

                let! unknown = byTag "Tag" (Some (Guid.CreateVersion7 ()))
                Expect.isEmpty unknown "an unknown tag matches nothing"
            }

            testAsync "amount matches a direction and sizes" {
                use app = newApp ()

                for value in [ 50m; -50m; -120m; 0m; 300m; -300m; 12.34m ] do
                    do!
                        create app.Client (transaction (string value) value)
                        |> Async.Ignore

                let matching direction minimum maximum =
                    searchSorted app.Client (amount direction minimum maximum)

                let! debits = matching "Debit" (Some 50m) (Some 200m)
                Expect.equal debits [ "-120"; "-50" ] "debits of 50 to 200"

                let! credits = matching "Credit" None None
                Expect.equal credits [ "12.34"; "300"; "50" ] "credits"

                let! large = matching "Any" (Some 100m) None
                Expect.equal large [ "-120"; "-300"; "300" ] "at least 100"

                let! small = matching "Any" None (Some 50m)

                Expect.equal
                    small
                    [ "-50"; "0"; "12.34"; "50" ]
                    "at most 50, including zero"

                let! exact = matching "Credit" (Some 12.34m) (Some 12.34m)
                Expect.equal exact [ "12.34" ] "equal bounds"

                let! debitsWithZero = matching "Debit" None (Some 0m)
                Expect.isEmpty debitsWithZero "zero is not a debit"
            }

            testAsync "criteria combine with AND" {
                use app = newApp ()

                for description, value in
                    [
                        "COUNTDOWN", -20m
                        "COUNTDOWN REFUND", 20m
                        "NEW WORLD", -20m
                    ] do
                    do!
                        create app.Client (transaction description value)
                        |> Async.Ignore

                let! matches =
                    search app.Client {
                        amount "Debit" None None with
                            Text = "countdown"
                    }

                Expect.equal matches [ "COUNTDOWN" ] "text and direction"
            }

            testAsync "only the caller's transactions match" {
                use app = newApp ()
                let other = app.ClientForUser "other-user"
                do! create other (transaction "Theirs" -1m) |> Async.Ignore
                do! create app.Client (transaction "Mine" -1m) |> Async.Ignore

                let! matches = search app.Client anyCriteria
                Expect.equal matches [ "Mine" ] "the caller's"
            }

            testAsync "pages cover every match once across same-day ties" {
                use app = newApp ()

                for day in [ 1; 2; 3 ] do
                    for n in 1..50 do
                        do!
                            create app.Client {
                                transaction $"{day}-{n}" -1m with
                                    Date = march day
                            }
                            |> Async.Ignore

                let! first = searchPage app.Client anyCriteria None

                Expect.equal
                    (List.length first.Transactions)
                    TransactionSearch.PageSize
                    "a full first page"

                Expect.isSome first.Cursor "a cursor after a full page"

                let! second = searchPage app.Client anyCriteria first.Cursor
                Expect.equal (List.length second.Transactions) 50 "the rest"
                Expect.isNone second.Cursor "no cursor on the last page"

                let all = first.Transactions @ second.Transactions

                Expect.equal
                    (all |> List.map _.Id |> List.distinct |> List.length)
                    150
                    "every match once"

                let order =
                    all
                    |> List.map (fun transaction ->
                        transaction.Date, transaction.Id.ToString ())

                Expect.equal
                    order
                    (List.sortWith
                        (fun (dateA, idA) (dateB, idB) ->
                            match compare dateB dateA with
                            | 0 -> String.CompareOrdinal (idB, idA)
                            | order -> order)
                        order)
                    "newest first, then by id"
            }

            testAsync "invalid criteria and malformed cursors are 400" {
                use app = newApp ()

                let! invalid =
                    post app.Client (amount "Any" (Some 2m) (Some 1m)) None

                Expect.equal
                    invalid.StatusCode
                    HttpStatusCode.BadRequest
                    "minimum above maximum"

                let! malformed = post app.Client anyCriteria (Some "nonsense")

                Expect.equal
                    malformed.StatusCode
                    HttpStatusCode.BadRequest
                    "malformed cursor"
            }
        ]
