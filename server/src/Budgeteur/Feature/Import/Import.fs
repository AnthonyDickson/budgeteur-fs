namespace Budgeteur.Feature.Import

open System

open Budgeteur.Domain.Account
open Budgeteur.Domain.Rule
open Budgeteur.Domain.Categorisation
open Budgeteur.Domain.Transaction

/// <summary>A statement row to insert as a transaction.</summary>
type NewTransaction = {
    Transaction : Transaction
    ImportHash : string
    /// <summary>The winning rule's tag, for a row that is not a
    /// transfer.</summary>
    Categorisation : Categorisation option
}

/// <summary>What an import did with the rows of its statements.</summary>
type ImportCounts = {
    /// <summary>Rows inserted as transactions, transfers included.</summary>
    Imported : int
    /// <summary>Rows the user had already imported, or that repeat an earlier
    /// row of the request.</summary>
    SkippedDuplicates : int
    /// <summary>Imported rows between the user's own accounts.</summary>
    Transfers : int
    /// <summary>Imported rows a rule tagged.</summary>
    TaggedByRules : int
}

/// <summary>The import workflow's rules, apart from the handler: which
/// accounts to create, which rows are duplicates, which are transfers, and
/// their tags. See decisions 4, 6, 8, and 9 in docs/csv-import.md.</summary>
module Import =
    /// <summary>The statements' accounts the user has no account for, once
    /// each, in the order the statements name them.</summary>
    let missingAccounts
        (userNumbers : Set<AccountNumber>)
        (statements : Statement list)
        : StatementAccount list =
        statements
        |> List.map _.Account
        |> List.distinctBy _.Number
        |> List.filter (fun account ->
            not (userNumbers.Contains account.Number))

    /// <summary>An account created on import: named after its number and
    /// product, current, with an unknown balance until its observations are
    /// recorded.</summary>
    let createAccount (id : Guid) (account : StatementAccount) : Account = {
        Id = id
        Number = Some account.Number
        Name = AccountName.ofNumber account.Number account.ProductName
        Term = Budgeteur.Domain.Term.Current
    }

    /// <summary>The rows to import: those whose hash the user does not have,
    /// keeping the first of rows that share a hash within the request. Returns
    /// them with each row's statement, and the number skipped.</summary>
    let dropDuplicates
        (userHashes : Set<string>)
        (statements : Statement list)
        : (Statement * StatementRow) list * int =
        let rows =
            statements
            |> List.collect (fun statement ->
                statement.Rows |> List.map (fun row -> statement, row))

        let kept, _ =
            rows
            |> List.fold
                (fun (kept, seen : Set<string>) (statement, row) ->
                    if seen.Contains row.ImportHash then
                        kept, seen
                    else
                        (statement, row) :: kept, seen.Add row.ImportHash)
                ([], userHashes)

        List.rev kept, List.length rows - List.length kept

    /// <summary>Whether a row moves money between the user's own accounts:
    /// its other party's account is one of theirs.</summary>
    let isTransfer
        (userNumbers : Set<AccountNumber>)
        (row : StatementRow)
        : bool =
        row.OtherPartyAccount |> Option.exists userNumbers.Contains

    /// <summary>The transactions to insert for the statements' new rows, and
    /// the counts. <c>accountIds</c> maps every account number of the user,
    /// including accounts this import creates, to its account. A transfer has
    /// no tag; any other row gets the winning rule's tag.</summary>
    let plan
        (newId : unit -> Guid)
        (accountIds : Map<AccountNumber, Guid>)
        (userHashes : Set<string>)
        (rules : Rule list)
        (statements : Statement list)
        : NewTransaction list * ImportCounts =
        let rows, skipped = dropDuplicates userHashes statements
        let userNumbers = accountIds |> Map.keys |> Set.ofSeq
        let winner = Rule.winner rules

        let transactions =
            rows
            |> List.map (fun (statement, row) ->
                let isTransfer = isTransfer userNumbers row

                let categorisation =
                    if isTransfer then
                        None
                    else
                        Categorisation.tagUntagged
                            (winner row.Description |> Option.map _.TagId)
                            None

                {
                    Transaction = {
                        Id = newId ()
                        Amount = row.Amount
                        Description = row.Description
                        Date = row.Date
                        IsTransfer = isTransfer
                        AccountId =
                            Map.tryFind statement.Account.Number accountIds
                    }
                    ImportHash = row.ImportHash
                    Categorisation = categorisation
                })

        transactions,
        {
            Imported = List.length transactions
            SkippedDuplicates = skipped
            Transfers =
                transactions
                |> List.filter _.Transaction.IsTransfer
                |> List.length
            TaggedByRules =
                transactions
                |> List.filter (fun transaction ->
                    Option.isSome transaction.Categorisation)
                |> List.length
        }
