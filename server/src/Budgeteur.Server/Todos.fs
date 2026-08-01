namespace Budgeteur.Server.Todos

open System

/// <summary>A todo item stored in the database.</summary>
type Todo = {
    /// <summary>Unique identifier for the todo item.</summary>
    Id : Guid

    /// <summary>The title or description of the todo.</summary>
    Title : string

    /// <summary>Whether the todo has been completed.</summary>
    Completed : bool

    /// <summary>UTC timestamp when the todo was created.</summary>
    CreatedAt : DateTime
}

/// <summary>Payload for updating an existing todo item.</summary>
type UpdateTodoRequest = { Title : string; Completed : bool }

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

    let private toTodo (row : main.Todos) : Todo = {
        Id = row.Id
        Title = row.Title
        Completed = row.Completed
        CreatedAt = DateTimeOffset.FromUnixTimeSeconds(row.CreatedAt).UtcDateTime
    }

    let private toRow (todo : Todo) (userId : string) : main.Todos = {
        Id = todo.Id
        UserId = userId
        Title = todo.Title
        Completed = todo.Completed
        CreatedAt = DateTimeOffset(todo.CreatedAt).ToUnixTimeSeconds ()
    }

    // ── Queries ────────────────────────────────────────────────────────────

    let getAll (store : Store) (userId : string) =
        task {
            try
                let! rows =
                    selectTask store.Db {
                        for t in main.Todos do
                            select t
                            where (t.UserId = userId)
                    }

                let todos = rows |> List.ofSeq |> List.map toTodo

                return Ok todos
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let get (store : Store) (id : Guid) (userId : string) =
        task {
            try
                let! result =
                    selectTask store.Db {
                        for t in main.Todos do
                            where (t.Id = id && t.UserId = userId)
                            tryHead
                    }

                let todo = result |> Option.map toTodo

                return Ok todo
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let insert (store : Store) (todo : Todo) (userId : string) =
        task {
            try
                let! _ =
                    insertTask store.Db {
                        for t in main.Todos do
                            entity (toRow todo userId)
                    }

                return Ok ()
            with
            | :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
                return Error (Conflict $"A todo with ID %O{todo.Id} already exists")
            | ex -> return Error (DatabaseError (ex.Message, Some ex))
        }

    let update (store : Store) (id : Guid) (userId : string) (title : string) (completed : bool) =
        task {
            try
                use! shared = store.Db.OpenContextAsync ()
                shared.BeginTransaction ()

                let! _rowsAffected =
                    updateTask shared {
                        for t in main.Todos do
                            set t.Title title
                            set t.Completed completed
                            where (t.Id = id && t.UserId = userId)
                    }

                let! result =
                    selectTask shared {
                        for t in main.Todos do
                            where (t.Id = id && t.UserId = userId)
                            tryHead
                    }

                shared.CommitTransaction ()

                let todo = result |> Option.map toTodo

                return Ok todo
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let delete (store : Store) (id : Guid) (userId : string) =
        task {
            try
                let! rows =
                    deleteTask store.Db {
                        for t in main.Todos do
                            where (t.Id = id && t.UserId = userId)
                    }

                let deleted = rows > 0

                return Ok deleted
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

    let deleteCompleted (store : Store) (userId : string) =
        task {
            try
                let! rowsAffected =
                    deleteTask store.Db {
                        for t in main.Todos do
                            where (t.Completed && t.UserId = userId)
                    }

                return Ok rowsAffected
            with ex ->
                return Error (DatabaseError (ex.Message, Some ex))
        }

module Validation =
    open Budgeteur.Server.DomainError

    [<Literal>]
    let private MaxTodoTitleLength = 256

    let private nonEmpty (title : string) =
        if String.IsNullOrWhiteSpace title then
            Error (ValidationFailed "Title cannot be null or just whitespace")
        else
            Ok title

    let private acceptableLength (title : string) =
        if title.Length > MaxTodoTitleLength then
            Error (
                ValidationFailed
                    $"Title is too long. Titles must be at most \
                    %i{MaxTodoTitleLength} characters, but got %i{title.Length}"
            )
        else
            Ok title

    /// <summary>Trim whitespace and then validate a Todo title. Returns the trimmed title.</summary>
    let validateAndTrimTitle (title : string) =
        title.Trim () |> nonEmpty |> Result.bind acceptableLength

    let validate (todo : Todo) =
        validateAndTrimTitle todo.Title
        |> Result.map (fun trimmedTitle -> { todo with Title = trimmedTitle })

module Api =
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
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
        let private handler (store : Store) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let! userId = Auth.getUserId ctx
                    let! items = Store.getAll store userId
                    let log = RequestLog.fromContext ctx

                    log.Info ($"Returned %i{List.length items} todos", LogProp.prop "count" (List.length items))
                    do! Json.write ctx items
                })

        let endpoint (store : Store) =
            route "/api/todos" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody typeof<Todo list>
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "List all todos"
                            op.Description <- "Returns every todo item in the store."
                            Task.CompletedTask
                )
            )

    module Get =
        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let! userId = Auth.getUserId ctx
                    let! todo = Store.get store id userId
                    let log = RequestLog.fromContext ctx

                    match todo with
                    | Some item ->
                        log.Info ($"Returned todo %O{id}", LogProp.prop "todoId" (id.ToString ()))
                        do! Json.write ctx item
                    | None ->
                        log.Warn ($"Todo %O{id} not found", LogProp.prop "todoId" (id.ToString ()))
                        return! Error (NotFound $"Todo %O{id} not found")
                })

        let endpoint (store : Store) =
            routef "/api/todos/{%O:guid}" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody typeof<Todo>
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Get a todo by ID"
                            op.Description <- "Returns a single todo item, or 404 if not found."
                            Task.CompletedTask
                )
            )

    module Create =
        let private handler (store : Store) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! userId = Auth.getUserId ctx
                    let! (todo : Todo) = Json.read ctx
                    let! todo = Validation.validate todo

                    let! () = Store.insert store todo userId
                    log.Info ($"Created todo %O{todo.Id}", LogProp.prop "todoId" (todo.Id.ToString ()))
                    ctx.SetStatusCode 201
                    do! Json.write ctx todo
                })

        let endpoint (store : Store) =
            route "/api/todos" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    requestBody = RequestBody typeof<Todo>,
                    responseBodies = [|
                        ResponseBody (typeof<Todo>, statusCode = 201)
                        ResponseBody (typeof<ApiError>, statusCode = 400)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 409)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Create a todo"
                            op.Description <- "Creates a new todo item and returns it with status 201."
                            Task.CompletedTask
                )
            )

    module Update =
        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! (req : UpdateTodoRequest) = Json.read ctx
                    let! userId = Auth.getUserId ctx

                    let! title = Validation.validateAndTrimTitle req.Title
                    let! updated = Store.update store id userId title req.Completed

                    match updated with
                    | Some updated ->
                        log.Info ($"Updated todo %O{id}", LogProp.prop "todoId" (id.ToString ()))
                        do! Json.write ctx updated
                    | None ->
                        log.Warn ($"Todo %O{id} not found", LogProp.prop "todoId" (id.ToString ()))
                        return! Error (NotFound $"Todo %O{id} not found")
                })

        let endpoint (store : Store) =
            routef "/api/todos/{%O:guid}" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    requestBody = RequestBody typeof<UpdateTodoRequest>,
                    responseBodies = [|
                        ResponseBody typeof<Todo>
                        ResponseBody (typeof<ApiError>, statusCode = 400)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Update a todo"
                            op.Description <- "Replaces the title and completed flag of an existing todo."
                            Task.CompletedTask
                )
            )

    module Delete =
        let private handler (store : Store) (id : Guid) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! userId = Auth.getUserId ctx
                    let! deleted = Store.delete store id userId

                    if deleted then
                        log.Info ($"Deleted todo %O{id}", LogProp.prop "todoId" (id.ToString ()))
                        ctx.SetStatusCode 204
                    else
                        log.Warn ($"Todo %O{id} not found", LogProp.prop "todoId" (id.ToString ()))
                        return! Error (NotFound $"Todo %O{id} not found")
                })

        let endpoint (store : Store) =
            routef "/api/todos/{%O:guid}" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody (typeof<unit>, statusCode = 204)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                        ResponseBody (typeof<ApiError>, statusCode = 404)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Delete a todo"
                            op.Description <- "Permanently removes a todo. Returns 204 on success."
                            Task.CompletedTask
                )
            )

    module DeleteCompleted =
        let private handler (store : Store) : EndpointHandler =
            Endpoint.handler (fun ctx ->
                taskResult {
                    let log = RequestLog.fromContext ctx
                    let! userId = Auth.getUserId ctx
                    let! rowsAffected = Store.deleteCompleted store userId

                    log.Info ($"Deleted %i{rowsAffected} completed todos", LogProp.prop "count" rowsAffected)
                    ctx.SetStatusCode 204
                })

        let endpoint (store : Store) =
            route "/api/todos/completed" (handler store)
            |> addOpenApi (
                OpenApiConfig (
                    responseBodies = [|
                        ResponseBody (typeof<unit>, statusCode = 204)
                        ResponseBody (typeof<ApiError>, statusCode = 401)
                    |],
                    configureOperation =
                        fun op _ _ ->
                            op.Summary <- "Delete all completed todo"
                            op.Description <- "Permanently removes all completed todos. Returns 204 on success."
                            Task.CompletedTask
                )
            )

    let endpoints (store : Store) : Oxpecker.RoutingTypes.Endpoint seq = [
        GET [ GetAll.endpoint store; Get.endpoint store ]
        POST [ Create.endpoint store ]
        PATCH [ Update.endpoint store ]
        DELETE [ Delete.endpoint store; DeleteCompleted.endpoint store ]
    ]

/// This module defines the public API of the Todos feature slice
[<RequireQualifiedAccess>]
module Todos =
    open Oxpecker

    open Budgeteur.Server.Auth

    type Store = Store.Store

    let endpoints (store : Store) =
        Api.endpoints store |> Seq.map (addFilter Auth.requireAuth)
