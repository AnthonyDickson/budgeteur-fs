namespace Budgeteur.Server.Transactions

open System

/// <summary>A transaction stored in the database.</summary>
type Transaction = {
    /// <summary>Unique identifier for the transaction item.</summary>
    Id : Guid

    Amount : decimal

    /// <summary>The title or description of the transaction.</summary>
    Description : string

    /// <summary>UTC timestamp when the transaction was created.</summary>
    CreatedAt : DateTime

    ImportHash : Option<string>
    AccountId : Option<Guid>
    CategoryId : Option<Guid>
}

module Store =
    open Budgeteur.Server.DomainError
    open Budgeteur.Server.Db
    open Microsoft.Data.Sqlite
    open SqlHydra.Query
    open SqlHydra.Query.SqliteExtensions

    type Store = { Db : QueryContextFactory }

    let create (connectionString : string) = {
        Db = QueryContextFactory.Create connectionString
    }

    // ── DB row ↔ API type mapping ──────────────────────────────────────────

    let private toTransaction (row : main.Transactions) : Transaction = {
        Id = row.Id
        Amount = row.Amount
        Description = row.Description
        CreatedAt = DateTimeOffset.FromUnixTimeSeconds(row.CreatedAt).UtcDateTime
        ImportHash = row.ImportHash
        AccountId = row.AccountId
        CategoryId = row.CategoryId
    }

    let private toRow (transaction : Transaction) (userId : string) : main.Transactions = {
        Id = transaction.Id
        UserId = userId
        Amount = transaction.Amount
        Description = transaction.Description
        CreatedAt = DateTimeOffset(transaction.CreatedAt).ToUnixTimeSeconds ()
        ImportHash = transaction.ImportHash
        AccountId = transaction.AccountId
        CategoryId = transaction.CategoryId
    }

    // ── Queries ────────────────────────────────────────────────────────────

    let getAll (store : Store) (userId : string) =
        task {
            try
                let! rows =
                    selectTask store.Db {
                        for t in main.Transactions do
                            select t
                            where (t.UserId = userId)
                    }

                let transactions = rows |> List.ofSeq |> List.map toTransaction

                return Ok transactions
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let get (store : Store) (id : Guid) (userId : string) =
        task {
            try
                let! result =
                    selectTask store.Db {
                        for t in main.Transactions do
                            where (t.Id = id && t.UserId = userId)
                            tryHead
                    }

                let transaction = result |> Option.map toTransaction

                return Ok transaction
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let insert (store : Store) (transaction : Transaction) (userId : string) =
        task {
            try
                let! _ =
                    insertTask store.Db {
                        for t in main.Transactions do
                            entity (toRow transaction userId)
                    }

                return Ok ()
            with
            | :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
                return Error (Conflict $"A transaction with ID %O{transaction.Id} already exists")
            | ex -> return Error (DatabaseError (ex.Message, Some ex))
        }

    let update (store : Store) (transaction : Transaction) (userId : string) =
        task {
            try
                use! shared = store.Db.OpenContextAsync ()
                shared.BeginTransaction ()

                let! _rowsAffected =
                    updateTask shared {
                        for t in main.Transactions do
                            entity (toRow transaction userId)
                            excludeColumn t.Id
                            where (t.Id = transaction.Id && t.UserId = userId)
                    }

                let! result =
                    selectTask shared {
                        for t in main.Transactions do
                            where (t.Id = transaction.Id && t.UserId = userId)
                            tryHead
                    }

                shared.CommitTransaction ()

                let transaction = result |> Option.map toTransaction

                return Ok transaction
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let delete (store : Store) (id : Guid) (userId : string) =
        task {
            try
                let! rows =
                    deleteTask store.Db {
                        for t in main.Transactions do
                            where (t.Id = id && t.UserId = userId)
                    }

                let deleted = rows > 0

                return Ok deleted
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

module Validation =
    open Budgeteur.Server.DomainError

    [<Literal>]
    let private MaxTransactionDescriptionLength = 256

    let private nonEmpty (description : string) =
        if String.IsNullOrWhiteSpace description then
            Error (ValidationFailed "Description cannot be null or just whitespace")
        else
            Ok description

    let private acceptableLength (description : string) =
        if description.Length > MaxTransactionDescriptionLength then
            Error (
                ValidationFailed
                    $"Title is too long. Titles must be at most \
                    %i{MaxTransactionDescriptionLength} characters, but got %i{description.Length}"
            )
        else
            Ok description

    /// <summary>Trim whitespace and then validate a transaction description. Returns the trimmed title.</summary>
    let validateAndTrimDescription (description : string) =
        description.Trim () |> nonEmpty |> Result.bind acceptableLength

    let validate (transaction : Transaction) =
        validateAndTrimDescription transaction.Description
        |> Result.map (fun trimmedDescription -> {
            transaction with
                Description = trimmedDescription
        })

module Api =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi

    open Budgeteur.Server.ApiError
    open Budgeteur.Server.Auth
    open Budgeteur.Server.DomainError
    open Budgeteur.Server.Endpoint
    open Budgeteur.Server.Json
    open Budgeteur.Server.RequestLogging
    open Store

    module GetAll =
        [<Literal>]
        let Path = "/api/transactions"

        let private handler (store : Store) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let! userId = Auth.getUserId ctx
                    let! items = Store.getAll store userId
                    let log = RequestLog.fromContext ctx

                    log.Info ($"Returned %i{List.length items} transactions", LogProp.prop "count" (List.length items))
                    do! Json.write ctx items
                })

        let endpoint (store : Store) =
            route Path (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody typeof<Transaction list>
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "List all transactions"
                            op.Description <- "Returns every transaction in the store."
                            op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                            Task.CompletedTask
                )
            )

    module Get =
        [<Literal>]
        let Path = "/api/transactions/{%O:guid}"

        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let! userId = Auth.getUserId ctx
                    let! transaction = Store.get store id userId
                    let log = RequestLog.fromContext ctx

                    match transaction with
                    | Some item ->
                        log.Info ($"Returned transaction %O{id}", LogProp.prop "transactionId" (id.ToString ()))
                        do! Json.write ctx item
                    | None ->
                        log.Warn ($"Transaction %O{id} not found", LogProp.prop "transactionId" (id.ToString ()))
                        return! Error (NotFound $"Transaction %O{id} not found")
                })

        let endpoint (store : Store) =
            routef Path (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody typeof<Transaction>
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Get a transaction by ID"
                            op.Description <- "Returns a single transaction item, or 404 if not found."
                            op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                            Task.CompletedTask
                )
            )

    module Create =
        [<Literal>]
        let Path = "/api/transactions"

        let private handler (store : Store) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! userId = Auth.getUserId ctx
                    let! (transaction : Transaction) = Json.read ctx
                    let! transaction = Validation.validate transaction

                    let! () = Store.insert store transaction userId

                    log.Info (
                        $"Created transaction %O{transaction.Id}",
                        LogProp.prop "transactionId" (transaction.Id.ToString ())
                    )

                    ctx.SetStatusCode 201
                    do! Json.write ctx transaction
                })

        let endpoint (store : Store) =
            route Path (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    requestBody = RequestBody typeof<Transaction>,
                    responseBodies = [|
                        ResponseBody (typeof<Transaction>, statusCode = 201)
                        ResponseBody (typeof<ApiError>, statusCode = 400)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 409)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Create a transaction"
                            op.Description <- "Creates a new transaction and returns it with status 201."
                            op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                            Task.CompletedTask
                )
            )

    module Update =
        [<Literal>]
        let Path = "/api/transactions/{%O:guid}"

        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! (req : Transaction) = Json.read ctx
                    let! userId = Auth.getUserId ctx

                    let! transaction = Validation.validate req
                    let! updated = Store.update store transaction userId

                    match updated with
                    | Some updated ->
                        log.Info ($"Updated transaction %O{id}", LogProp.prop "transactionId" (id.ToString ()))
                        do! Json.write ctx updated
                    | None ->
                        log.Warn ($"Transaction %O{id} not found", LogProp.prop "transactionId" (id.ToString ()))
                        return! Error (NotFound $"Transaction %O{id} not found")
                })

        let endpoint (store : Store) =
            routef Path (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    requestBody = RequestBody typeof<Transaction>,
                    responseBodies = [|
                        ResponseBody typeof<Transaction>
                        ResponseBody (typeof<ApiError>, statusCode = 400)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Update a transaction"
                            op.Description <- "Replaces the transaction."
                            op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                            Task.CompletedTask
                )
            )

    module Delete =
        [<Literal>]
        let Path = "/api/transactions/{%O:guid}"

        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! userId = Auth.getUserId ctx
                    let! deleted = Store.delete store id userId

                    if deleted then
                        log.Info ($"Deleted transaction %O{id}", LogProp.prop "transactionId" (id.ToString ()))
                        ctx.SetStatusCode 204
                    else
                        log.Warn ($"Transaction %O{id} not found", LogProp.prop "transactionId" (id.ToString ()))
                        return! Error (NotFound $"Transaction %O{id} not found")
                })

        let endpoint (store : Store) =
            routef Path (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody (typeof<unit>, statusCode = 204)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Delete a transaction"
                            op.Description <- "Permanently removes a transaction. Returns 204 on success."
                            op.Tags <- HashSet [ OpenApiTagReference "Transactions" ]
                            Task.CompletedTask
                )
            )

    let endpoints (store : Store) : Oxpecker.RoutingTypes.Endpoint seq = [
        GET [ GetAll.endpoint store; Get.endpoint store ]
        POST [ Create.endpoint store ]
        PUT [ Update.endpoint store ]
        DELETE [ Delete.endpoint store ]
    ]

/// This module defines the public API of the Transactions feature slice
[<RequireQualifiedAccess>]
module Transactions =
    open Oxpecker

    open Budgeteur.Server.Auth

    type Store = Store.Store

    let endpoints (store : Store) =
        Api.endpoints store |> Seq.map (addFilter Auth.requireAuth)
