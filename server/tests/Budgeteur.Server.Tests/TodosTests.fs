namespace Budgeteur.Server.Tests

module TodosTests =
    open System
    open System.Net
    open Budgeteur.Server.Coders
    open Budgeteur.Server.Tests
    open Budgeteur.Server.Todos
    open Expecto

    let private todo (id : Guid) (title : string) (completed : bool) = {
        Id = id
        Title = title
        Completed = completed
        CreatedAt = DateTime.UtcNow
    }

    let newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTodos)

    [<Tests>]
    let tests =
        testList "Todos" [
            testCaseAsync "GET /api/todos returns empty list when no todos exist"
            <| async {
                use app = newApp ()

                let! response = app.Client.GetAsync "/api/todos" |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask
                let result = Decode.fromString<Todo list> body

                Expect.equal result (Ok []) "body should be empty list"
            }

            testCaseAsync "GET /api/todos returns seeded todos"
            <| async {
                use app = newApp ()

                let expected = todo (Guid.NewGuid ()) "Buy milk" false
                let! _ = TestHttp.postJson app.Client "/api/todos" expected |> Async.AwaitTask

                let! response = app.Client.GetAsync "/api/todos" |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromString<Todo list> body with
                | Ok [ item ] ->
                    Expect.equal expected.Id item.Id "id should match"
                    Expect.equal expected.Title item.Title "title should match"
                    Expect.equal expected.Completed item.Completed "completed should match"
                | _ -> failtest "Expected one todo"
            }

            testCaseAsync "GET /api/todos/{id} returns the todo"
            <| async {
                use app = newApp ()

                let expected = todo (Guid.NewGuid ()) "Walk dog" true
                let! _ = TestHttp.postJson app.Client "/api/todos" expected |> Async.AwaitTask

                let! response = app.Client.GetAsync $"/api/todos/{expected.Id}" |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromString<Todo> body with
                | Ok item ->
                    Expect.equal expected.Id item.Id "id should match"
                    Expect.equal expected.Title item.Title "title should match"
                    Expect.equal expected.Completed item.Completed "completed should match"
                | Error err -> failtest err
            }

            testCaseAsync "GET /api/todos/{id} returns 404 for missing todo"
            <| async {
                use app = newApp ()

                let! response = app.Client.GetAsync $"/api/todos/{Guid.NewGuid ()}" |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.NotFound "status code should be 404"
            }

            testCaseAsync "POST /api/todos creates a todo"
            <| async {
                use app = newApp ()

                let input = todo (Guid.NewGuid ()) "Learn F#" false

                let! response = TestHttp.postJson app.Client "/api/todos" input |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.Created "status code should be 201"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromString<Todo> body with
                | Ok created ->
                    Expect.equal input.Id created.Id "id should match"
                    Expect.equal input.Title created.Title "title should match"
                    Expect.equal input.Completed created.Completed "completed should match"
                | Error err -> failtest err
            }

            testCaseAsync "PATCH /api/todos/{id} updates a todo"
            <| async {
                use app = newApp ()

                let original = todo (Guid.NewGuid ()) "Old title" false
                let! _ = TestHttp.postJson app.Client "/api/todos" original |> Async.AwaitTask

                let update : UpdateTodoRequest = {
                    Title = "New title"
                    Completed = true
                }

                let! response =
                    TestHttp.patchJson app.Client $"/api/todos/{original.Id}" update
                    |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.OK "status code should be 200"

                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromString<Todo> body with
                | Ok updated ->
                    Expect.equal original.Id updated.Id "id should match"
                    Expect.equal update.Title updated.Title "title should match"
                    Expect.equal update.Completed updated.Completed "completed should match"
                | Error err -> failtest err
            }

            testCaseAsync "DELETE /api/todos/{id} removes the todo"
            <| async {
                use app = newApp ()

                let item = todo (Guid.NewGuid ()) "To delete" false
                let! _ = TestHttp.postJson app.Client "/api/todos" item |> Async.AwaitTask

                let! deleteResponse = app.Client.DeleteAsync $"/api/todos/{item.Id}" |> Async.AwaitTask

                Expect.equal deleteResponse.StatusCode HttpStatusCode.NoContent "delete status should be 204"

                let! getResponse = app.Client.GetAsync $"/api/todos/{item.Id}" |> Async.AwaitTask

                Expect.equal getResponse.StatusCode HttpStatusCode.NotFound "get after delete should be 404"
            }

            testCaseAsync "DELETE /api/todos/completed removes only completed todos"
            <| async {
                use app = newApp ()

                let completed = todo (Guid.NewGuid ()) "Done task" true
                let active = todo (Guid.NewGuid ()) "Active task" false
                let! _ = TestHttp.postJson app.Client "/api/todos" completed |> Async.AwaitTask
                let! _ = TestHttp.postJson app.Client "/api/todos" active |> Async.AwaitTask

                let! deleteResponse = app.Client.DeleteAsync "/api/todos/completed" |> Async.AwaitTask

                Expect.equal deleteResponse.StatusCode HttpStatusCode.NoContent "delete status should be 204"

                let! response = app.Client.GetAsync "/api/todos" |> Async.AwaitTask
                let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

                match Decode.fromString<Todo list> body with
                | Ok items ->
                    Expect.equal (List.length items) 1 "should have 1 remaining todo"
                    Expect.equal active.Id items[0].Id "remaining todo id should match"
                | Error err -> failtest err
            }
        ]
