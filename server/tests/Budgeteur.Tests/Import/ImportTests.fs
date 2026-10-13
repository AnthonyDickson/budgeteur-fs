namespace Budgeteur.Tests.Import

module ImportTests =
    open System
    open Expecto

    open Budgeteur.Domain.Account
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Rule
    open Budgeteur.Domain.TagAssignment
    open Budgeteur.Domain.Transaction
    open Budgeteur.Feature.Import

    let private number text =
        AccountNumber.create text |> Result.defaultWith (failtestf "%A")

    let private chequing = number "12-3456-0789012-000"
    let private savings = number "12-3456-0789012-001"

    let private row hash description (otherParty : AccountNumber option) = {
        Line = 2
        Date = DateOnly (2026, 3, 1)
        Description =
            TransactionDescription.create description
            |> Result.defaultWith (failtestf "%A")
        Amount = Money.create -10m
        Balance = None
        OtherPartyAccount = otherParty
        ImportHash = hash
    }

    let private statement account rows = {
        FileName = "statement.csv"
        Format = "Kiwibank"
        Account = { Number = account; ProductName = None }
        Rows = rows
        Observations = []
    }

    [<Tests>]
    let tests =
        testList "Import workflow" [
            testCase "duplicates are dropped against the user and the request"
            <| fun () ->
                let statements = [
                    statement chequing [
                        row "a" "CAFE" None
                        row "b" "CAFE" None
                    ]
                    // An overlapping export of the same account.
                    statement chequing [
                        row "b" "CAFE" None
                        row "c" "CAFE" None
                    ]
                ]

                let kept, skipped =
                    Import.dropDuplicates (set [ "a" ]) statements

                Expect.equal
                    (kept |> List.map (fun (_, row) -> row.ImportHash))
                    [ "b"; "c" ]
                    "the user's hash and the request's repeat are dropped"

                Expect.equal skipped 2 "two rows skipped"

            testCase "accounts are created once for numbers the user lacks"
            <| fun () ->
                let statements = [
                    statement chequing []
                    statement savings []
                    statement savings []
                ]

                Expect.equal
                    (Import.missingAccounts (set [ chequing ]) statements
                     |> List.map _.Number)
                    [ savings ]
                    "savings, once"

            testCase "a transfer is marked and untagged, other rows get tags"
            <| fun () ->
                let tagId = Guid.NewGuid ()

                let rule = {
                    Id = Guid.NewGuid ()
                    Pattern =
                        RulePattern.create "TRANSFER"
                        |> Result.defaultWith (failtestf "%A")
                    TagId = tagId
                }

                let accountIds =
                    Map.ofList [
                        chequing, Guid.NewGuid ()
                        savings, Guid.NewGuid ()
                    ]

                let transactions, counts =
                    Import.plan Guid.NewGuid accountIds Set.empty [ rule ] [
                        statement chequing [
                            row "a" "TRANSFER TO SAVINGS" (Some savings)
                            row
                                "b"
                                "TRANSFER TO JANE"
                                (Some (number "06-6543-0987654-00"))
                            row "c" "CAFE" None
                        ]
                    ]

                Expect.equal
                    (transactions
                     |> List.map (fun t ->
                         t.Transaction.IsTransfer, t.Assignment))
                    [
                        true, None
                        false,
                        Some {
                            TagId = tagId
                            Source = TagSource.Rule
                        }
                        false, None
                    ]
                    "only the transfer to the user's own account is marked"

                Expect.equal
                    counts
                    {
                        Imported = 3
                        SkippedDuplicates = 0
                        Transfers = 1
                        TaggedByRules = 1
                    }
                    "the counts"

                Expect.isTrue
                    (transactions
                     |> List.forall (fun t ->
                         t.Transaction.AccountId =
                             Map.tryFind chequing accountIds))
                    "every transaction is in the statement's account"
        ]
