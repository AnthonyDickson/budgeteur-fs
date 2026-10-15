namespace Budgeteur.Tests.Transaction

module SearchTests =
    open System
    open Expecto

    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Rule
    open Budgeteur.Feature.Transaction
    open Budgeteur.Shared.DomainError

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

    let private request (criteria : SearchCriteriaRequest) : SearchRequest = {
        Criteria = criteria
        Today = DateOnly (2026, 1, 15)
        Cursor = None
    }

    let private validSearch (req : SearchRequest) =
        match TransactionSearch.validate req with
        | Ok (search, _) -> search
        | Error error -> failtestf "Expected a valid search, got %A" error

    /// <summary>Expect the request to fail validation with a message
    /// containing each part.</summary>
    let private expectInvalid (parts : string list) (req : SearchRequest) =
        match TransactionSearch.validate req with
        | Error (ValidationFailed message) ->
            for part in parts do
                Expect.stringContains message part "error message"
        | other -> failtestf "Expected a validation failure, got %A" other

    let private date (year : int) (month : int) (day : int) =
        Some (DateOnly (year, month, day))

    let private preset (today : DateOnly) (preset : string) =
        let search =
            validSearch {
                request {
                    anyCriteria with
                        Dates = {
                            Preset = preset
                            From = None
                            To = None
                        }
                } with
                    Today = today
            }

        search.From, search.To

    let private custom (from : DateOnly option) (``to`` : DateOnly option) = {
        anyCriteria with
            Dates = {
                Preset = "Custom"
                From = from
                To = ``to``
            }
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

    let private cursor : Cursor = {
        Date = DateOnly (2026, 3, 8)
        Id = Guid.CreateVersion7 ()
    }

    [<Tests>]
    let tests =
        testList "TransactionSearch" [
            testCase "no criteria match every transaction"
            <| fun () ->
                let search = validSearch (request anyCriteria)

                Expect.equal
                    search
                    {
                        Text = None
                        From = None
                        To = None
                        Account = AccountCriterion.Any
                        Tag = TagCriterion.Any
                        Direction = Direction.Any
                        Minimum = None
                        Maximum = None
                    }
                    "search"

            testCase "blank text sets no criterion"
            <| fun () ->
                let search =
                    validSearch (request { anyCriteria with Text = "  " })

                Expect.isNone search.Text "text"

            testCase "text is trimmed"
            <| fun () ->
                let search =
                    validSearch (request { anyCriteria with Text = " count " })

                Expect.equal
                    (Option.map RulePattern.value search.Text)
                    (Some "count")
                    "text"

            testCase "text is validated like a rule pattern"
            <| fun () ->
                request {
                    anyCriteria with
                        Text = String.replicate 129 "a"
                }
                |> expectInvalid [ "too long" ]

            testCase "this and last month"
            <| fun () ->
                let today = DateOnly (2026, 1, 15)

                Expect.equal
                    (preset today "ThisMonth")
                    (date 2026 1 1, date 2026 1 31)
                    "this month"

                Expect.equal
                    (preset today "LastMonth")
                    (date 2025 12 1, date 2025 12 31)
                    "last month crosses the year"

            testCase "this and last year"
            <| fun () ->
                let today = DateOnly (2026, 1, 15)

                Expect.equal
                    (preset today "ThisYear")
                    (date 2026 1 1, date 2026 12 31)
                    "this year"

                Expect.equal
                    (preset today "LastYear")
                    (date 2025 1 1, date 2025 12 31)
                    "last year"

            testCase "financial years start on 1 April"
            <| fun () ->
                let march = DateOnly (2026, 3, 31)
                let april = DateOnly (2026, 4, 1)

                Expect.equal
                    (preset march "ThisFinancialYear")
                    (date 2025 4 1, date 2026 3 31)
                    "this financial year in March"

                Expect.equal
                    (preset march "LastFinancialYear")
                    (date 2024 4 1, date 2025 3 31)
                    "last financial year in March"

                Expect.equal
                    (preset april "ThisFinancialYear")
                    (date 2026 4 1, date 2027 3 31)
                    "this financial year in April"

            testCase "any time has no days"
            <| fun () ->
                Expect.equal
                    (preset (DateOnly (2026, 1, 15)) "AnyTime")
                    (None, None)
                    "any time"

            testCase "custom dates are optional and inclusive"
            <| fun () ->
                let search = validSearch (request (custom (date 2026 3 8) None))

                Expect.equal
                    (search.From, search.To)
                    (date 2026 3 8, None)
                    "from"

                let search =
                    validSearch (
                        request (custom (date 2026 3 8) (date 2026 3 8))
                    )

                Expect.equal
                    (search.From, search.To)
                    (date 2026 3 8, date 2026 3 8)
                    "one day"

            testCase "a custom first day after the last day is invalid"
            <| fun () ->
                request (custom (date 2026 3 9) (date 2026 3 8))
                |> expectInvalid [ "first day" ]

            testCase "a preset with days is invalid"
            <| fun () ->
                request {
                    anyCriteria with
                        Dates = {
                            Preset = "ThisMonth"
                            From = date 2026 1 1
                            To = None
                        }
                }
                |> expectInvalid [ "Only custom dates" ]

            testCase "an unknown preset is invalid"
            <| fun () ->
                request {
                    anyCriteria with
                        Dates = {
                            Preset = "Fortnight"
                            From = None
                            To = None
                        }
                }
                |> expectInvalid [ "Fortnight" ]

            testCase "account states take an id only for one account"
            <| fun () ->
                let id = Guid.CreateVersion7 ()

                let account state id = {
                    anyCriteria with
                        Account = { State = state; Id = id }
                }

                Expect.equal
                    (validSearch (request (account "Account" (Some id))))
                        .Account
                    (AccountCriterion.Account id)
                    "one account"

                Expect.equal
                    (validSearch (request (account "NoAccount" None))).Account
                    AccountCriterion.NoAccount
                    "no account"

                request (account "Account" None)
                |> expectInvalid [ "needs an id" ]

                request (account "NoAccount" (Some id))
                |> expectInvalid [ "takes no id" ]

                request (account "Savings" None) |> expectInvalid [ "Savings" ]

            testCase "tag states take an id only for one tag"
            <| fun () ->
                let id = Guid.CreateVersion7 ()

                let tag state id = {
                    anyCriteria with
                        Tag = { State = state; Id = id }
                }

                Expect.equal
                    (validSearch (request (tag "Tag" (Some id)))).Tag
                    (TagCriterion.Tag id)
                    "one tag"

                for state, criterion in
                    [
                        "WithoutTag", TagCriterion.WithoutTag
                        "Untagged", TagCriterion.Untagged
                        "Dismissed", TagCriterion.Dismissed
                        "Transfer", TagCriterion.Transfer
                    ] do
                    Expect.equal
                        (validSearch (request (tag state None))).Tag
                        criterion
                        state

                request (tag "Tag" None) |> expectInvalid [ "needs an id" ]

                request (tag "Untagged" (Some id))
                |> expectInvalid [ "takes no id" ]

            testCase "sizes are money"
            <| fun () ->
                let search =
                    validSearch (request (amount "Debit" (Some 50m) (Some 50m)))

                Expect.equal search.Direction Direction.Debit "direction"

                Expect.equal
                    (search.Minimum, search.Maximum)
                    (Some (Money.create 50m), Some (Money.create 50m))
                    "equal bounds"

                request (amount "Any" (Some -1m) None)
                |> expectInvalid [ "minimum cannot be negative" ]

                request (amount "Any" None (Some 1.005m))
                |> expectInvalid [ "maximum can have at most two" ]

                request (amount "Any" (Some 200m) (Some 50m))
                |> expectInvalid [ "minimum cannot be more than the maximum" ]

                request (amount "Sideways" None None)
                |> expectInvalid [ "Sideways" ]

            testCase "every failure is reported"
            <| fun () ->
                request {
                    amount "Sideways" None None with
                        Account = { State = "Account"; Id = None }
                }
                |> expectInvalid [ "Sideways"; "needs an id" ]

            testCase "a cursor round trips"
            <| fun () ->
                let _, parsed =
                    TransactionSearch.validate {
                        request anyCriteria with
                            Cursor = Some (Cursor.toString cursor)
                    }
                    |> Result.defaultWith (fun error ->
                        failtestf "Expected a valid search, got %A" error)

                Expect.equal parsed (Some cursor) "cursor"

            testCase "a malformed cursor is invalid"
            <| fun () ->
                for value in
                    [
                        "nonsense"
                        $"2026-13-01_{cursor.Id:D}"
                        "2026-03-08_not-a-guid"
                        $"2026-03-08_{cursor.Id:D}_extra"
                    ] do
                    {
                        request anyCriteria with
                            Cursor = Some value
                    }
                    |> expectInvalid [ "cursor is malformed" ]

            testCase "a page holds up to the page size and a cursor after it"
            <| fun () ->
                let matches = List.init 101 id

                let toCursor (n : int) = {
                    cursor with
                        Date = cursor.Date.AddDays -n
                }

                let page, next = TransactionSearch.page toCursor matches
                Expect.equal page (List.init 100 id) "page"
                Expect.equal next (Some (toCursor 99)) "next"

                let page, next =
                    TransactionSearch.page toCursor (List.init 100 id)

                Expect.equal (List.length page) 100 "last page"
                Expect.isNone next "no cursor on the last page"
        ]
