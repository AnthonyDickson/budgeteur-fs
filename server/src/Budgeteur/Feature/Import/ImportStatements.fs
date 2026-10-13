namespace Budgeteur.Feature.Import

open System.ComponentModel.DataAnnotations

/// <summary>A CSV file, read as UTF-8 text by the client.</summary>
type ImportFileRequest = {
    /// <summary>The file's name, used in error messages.</summary>
    Name : string

    /// <summary>The file's text.</summary>
    Content : string
}

/// <summary>Payload for importing bank statements.</summary>
type ImportRequest = {
    /// <summary>One statement per file.</summary>
    [<MinLength(1)>]
    Files : ImportFileRequest list
}

/// <summary>An account the import created for a statement whose account
/// number the user had no account for.</summary>
type CreatedAccountResponse = {
    Id : System.Guid
    /// <summary>The account number, followed by the product name when the
    /// statement gives one.</summary>
    Name : string
    /// <summary>The account number in canonical form.</summary>
    Number : string
}

/// <summary>What the import did.</summary>
type ImportResponse = {
    /// <summary>Rows inserted as transactions, transfers included.</summary>
    Imported : int

    /// <summary>Rows already imported, or repeated within the
    /// request.</summary>
    SkippedDuplicates : int

    /// <summary>Imported rows between the user's own accounts, marked as
    /// transfers and left untagged.</summary>
    Transfers : int

    /// <summary>Imported rows a rule tagged.</summary>
    TaggedByRules : int

    /// <summary>The accounts the import created.</summary>
    AccountsCreated : CreatedAccountResponse list
}

module ImportStatements =
    open System
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.AspNetCore.Http.Metadata
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Account
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.DomainError
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/imports"

    /// <summary>The request body limit for this endpoint: a year of
    /// statements fits, and it matches nginx's default
    /// <c>client_max_body_size</c>. Every other endpoint keeps the server's
    /// 64 KB. See decision 10 in docs/csv-import.md.</summary>
    [<Literal>]
    let MaxBodySize = 1_048_576L

    let private requestSizeLimit = {
        new IRequestSizeLimitMetadata with
            member _.MaxRequestBodySize = Nullable MaxBodySize
    }

    let private loadAccounts (ctx : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask ctx {
                    for a in main.Accounts do
                        where (a.UserId = userId)
                }

            return rows |> Seq.map AccountCodec.fromRow |> List.ofSeq
        }

    let private loadHashes (ctx : QueryContext) (userId : string) =
        task {
            let! hashes =
                selectTask ctx {
                    for t in main.Transactions do
                        where (t.UserId = userId)
                        select t.ImportHash
                }

            return hashes |> Seq.choose id |> Set.ofSeq
        }

    let private loadRules (ctx : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask ctx {
                    for r in main.Rules do
                        where (r.UserId = userId)
                }

            return rows |> Seq.map RuleCodec.fromRow |> List.ofSeq
        }

    /// <summary>Import the statements in one database transaction: find or
    /// create each statement's account, drop duplicates, mark transfers,
    /// insert the transactions with their rule tags, and record the balance
    /// observations. Microsoft.Data.Sqlite begins it with <c>BEGIN
    /// IMMEDIATE</c>, so a concurrent import cannot insert the same hashes
    /// between the check and the write. See decision 8 in
    /// docs/csv-import.md.</summary>
    let private import
        (queryContext : QueryContextFactory)
        (userId : string)
        (statements : Statement list)
        =
        task {
            use! ctx = queryContext.OpenContextAsync ()
            ctx.BeginTransaction ()

            let! accounts = loadAccounts ctx userId

            let created =
                Import.missingAccounts
                    (accounts |> List.choose _.Number |> Set.ofList)
                    statements
                |> List.map (fun account ->
                    Import.createAccount (Guid.CreateVersion7 ()) account)

            for account in created do
                let! _ =
                    insertTask ctx {
                        for a in main.Accounts do
                            entity (AccountCodec.toRow account userId)
                    }

                ()

            let accountIds =
                accounts @ created
                |> List.choose (fun account ->
                    account.Number
                    |> Option.map (fun number -> number, account.Id))
                |> Map.ofList

            let! hashes = loadHashes ctx userId
            let! rules = loadRules ctx userId

            let transactions, counts =
                Import.plan
                    Guid.CreateVersion7
                    accountIds
                    hashes
                    rules
                    statements

            for transaction in transactions do
                let row =
                    TransactionCodec.toRow
                        transaction.Transaction
                        userId
                        (Some transaction.ImportHash)

                let! _ =
                    insertTask ctx {
                        for t in main.Transactions do
                            entity row
                    }

                do!
                    CategorisationStore.save
                        ctx
                        userId
                        transaction.Transaction.Id
                        transaction.Categorisation

            for statement in statements do
                let accountId = accountIds[statement.Account.Number]

                for observation in statement.Observations do
                    do!
                        BalanceObservationStore.record
                            ctx
                            userId
                            accountId
                            observation

            ctx.CommitTransaction ()
            return counts, created
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let log = RequestLog.fromContext ctx
                let! userId = Auth.getUserId ctx
                let! (req : ImportRequest) = Json.read ctx

                do!
                    req.Files
                    |> List.isEmpty
                    |> Result.requireFalse (
                        ValidationFailed "Choose at least one file to import"
                    )

                let! statements =
                    req.Files
                    |> List.map (fun file -> file.Name, file.Content)
                    |> Statement.parseAll Formats.all
                    |> Result.mapError (fun errors ->
                        errors
                        |> List.map ImportError.describe
                        |> String.concat "\n"
                        |> ValidationFailed)

                let! counts, created = import queryContext userId statements

                log.Info (
                    $"Imported %i{counts.Imported} transactions from \
                    %i{List.length statements} statements",
                    LogProp.prop "imported" counts.Imported,
                    LogProp.prop "skippedDuplicates" counts.SkippedDuplicates,
                    LogProp.prop "transfers" counts.Transfers,
                    LogProp.prop "taggedByRules" counts.TaggedByRules,
                    LogProp.prop "accountsCreated" (List.length created)
                )

                do!
                    Json.write ctx {
                        Imported = counts.Imported
                        SkippedDuplicates = counts.SkippedDuplicates
                        Transfers = counts.Transfers
                        TaggedByRules = counts.TaggedByRules
                        AccountsCreated =
                            created
                            |> List.map (fun account -> {
                                Id = account.Id
                                Name = AccountName.value account.Name
                                Number =
                                    account.Number
                                    |> Option.map AccountNumber.value
                                    |> Option.defaultValue ""
                            })
                    }
            })

    let private configureOperation (op : OpenApiOperation) _ _ =
        op.Summary <- "Import bank statements"

        op.Description <-
            "Imports CSV bank statements in one database transaction: \
            accounts are found by number or created, rows already imported \
            are skipped, transfers between the user's accounts are marked, \
            rules tag the rest, and statement balances are recorded. A file \
            in no known format, or any row that cannot be read, fails the \
            whole request with 400, listing every problem. The request body \
            may be up to 1 MB."

        op.Tags <- HashSet [ OpenApiTagReference "Imports" ]

        Task.CompletedTask

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addMetadata requestSizeLimit
        |> addOpenApi (
            OpenApiConfig (
                requestBody = RequestBody typeof<ImportRequest>,
                responseBodies = [|
                    ResponseBody typeof<ImportResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 400)
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                    ResponseBody (typeof<ApiError>, statusCode = 409)
                |],
                configureOperation = configureOperation
            )
        )
