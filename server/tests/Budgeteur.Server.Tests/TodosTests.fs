namespace Budgeteur.Server.Tests

open System
open System.Net
open System.Net.Http
open System.Text
open System.Threading.Tasks
open Xunit
open Budgeteur.Server.Coders
open Budgeteur.Server.Todos

type TodosTests (fixture : TestApp) =
    let client = fixture.Client

    let todo (id : Guid) (title : string) (completed : bool) = {
        Id = id
        Title = title
        Completed = completed
        CreatedAt = DateTime.UtcNow
    }

    let postJson (url : string) (value : 'T) =
        let json = Encode.toString value
        let content = new StringContent (json, Encoding.UTF8, "application/json")
        client.PostAsync (url, content)

    let patchJson (url : string) (value : 'T) =
        let json = Encode.toString value
        let content = new StringContent (json, Encoding.UTF8, "application/json")
        client.PatchAsync (url, content)

    do fixture.CleanDatabase ()

    interface IClassFixture<TestApp>

    [<Fact>]
    member _.``GET /api/todos returns empty list when no todos exist`` () =
        task {
            // Given an empty database
            fixture.CleanDatabase ()

            // When getting all todos
            let! response = client.GetAsync "/api/todos"

            // Then the response is 200 OK with an empty list
            Assert.Equal (HttpStatusCode.OK, response.StatusCode)
            let! body = response.Content.ReadAsStringAsync ()
            let result = Decode.fromString<Todo list> body
            Assert.Equal (Ok [], result)
        }

    [<Fact>]
    member _.``GET /api/todos returns seeded todos`` () =
        task {
            // Given a todo exists in the database
            fixture.CleanDatabase ()
            let expected = todo (Guid.NewGuid ()) "Buy milk" false
            let! _ = postJson "/api/todos" expected

            // When getting all todos
            let! response = client.GetAsync "/api/todos"

            // Then the response is 200 OK with the matching todo
            Assert.Equal (HttpStatusCode.OK, response.StatusCode)
            let! body = response.Content.ReadAsStringAsync ()

            match Decode.fromString<Todo list> body with
            | Ok [ item ] ->
                Assert.Equal (expected.Id, item.Id)
                Assert.Equal (expected.Title, item.Title)
                Assert.Equal (expected.Completed, item.Completed)
            | _ -> Assert.True (false, "Expected one todo")
        }

    [<Fact>]
    member _.``GET /api/todos/{id} returns the todo`` () =
        task {
            // Given a todo exists in the database
            fixture.CleanDatabase ()
            let expected = todo (Guid.NewGuid ()) "Walk dog" true
            let! _ = postJson "/api/todos" expected

            // When getting the todo by its ID
            let! response = client.GetAsync $"/api/todos/{expected.Id}"

            // Then the response is 200 OK with the matching todo
            Assert.Equal (HttpStatusCode.OK, response.StatusCode)
            let! body = response.Content.ReadAsStringAsync ()

            match Decode.fromString<Todo> body with
            | Ok item ->
                Assert.Equal (expected.Id, item.Id)
                Assert.Equal (expected.Title, item.Title)
                Assert.Equal (expected.Completed, item.Completed)
            | Error err -> Assert.True (false, err)
        }

    [<Fact>]
    member _.``GET /api/todos/{id} returns 404 for missing todo`` () =
        task {
            // Given an empty database
            fixture.CleanDatabase ()

            // When getting a todo by a non-existent ID
            let! response = client.GetAsync $"/api/todos/{Guid.NewGuid ()}"

            // Then the response is 404 Not Found
            Assert.Equal (HttpStatusCode.NotFound, response.StatusCode)
        }

    [<Fact>]
    member _.``POST /api/todos creates a todo`` () =
        task {
            // Given an empty database and a new todo
            fixture.CleanDatabase ()
            let input = todo (Guid.NewGuid ()) "Learn F#" false
            // When creating the todo via POST
            let! response = postJson "/api/todos" input
            // Then the response is 201 Created with the matching todo
            Assert.Equal (HttpStatusCode.Created, response.StatusCode)
            let! body = response.Content.ReadAsStringAsync ()

            match Decode.fromString<Todo> body with
            | Ok created ->
                Assert.Equal (input.Id, created.Id)
                Assert.Equal (input.Title, created.Title)
                Assert.Equal (input.Completed, created.Completed)
            | Error err -> Assert.True (false, err)
        }

    [<Fact>]
    member _.``PATCH /api/todos/{id} updates a todo`` () =
        task {
            // Given an existing todo in the database
            fixture.CleanDatabase ()
            let original = todo (Guid.NewGuid ()) "Old title" false
            let! _ = postJson "/api/todos" original

            let update : UpdateTodoRequest = {
                Title = "New title"
                Completed = true
            }

            // When patching the todo with updated fields
            let! response = patchJson $"/api/todos/{original.Id}" update

            // Then the response is 200 OK with the updated todo
            Assert.Equal (HttpStatusCode.OK, response.StatusCode)
            let! body = response.Content.ReadAsStringAsync ()

            match Decode.fromString<Todo> body with
            | Ok updated ->
                Assert.Equal (original.Id, updated.Id)
                Assert.Equal (update.Title, updated.Title)
                Assert.Equal (update.Completed, updated.Completed)
            | Error err -> Assert.True (false, err)
        }

    [<Fact>]
    member _.``DELETE /api/todos/{id} removes the todo`` () =
        task {
            // Given a todo exists in the database
            fixture.CleanDatabase ()
            let item = todo (Guid.NewGuid ()) "To delete" false
            let! _ = postJson "/api/todos" item

            // When deleting the todo by its ID
            let! deleteResponse = client.DeleteAsync $"/api/todos/{item.Id}"

            // Then the delete returns 204 No Content and the todo is gone
            Assert.Equal (HttpStatusCode.NoContent, deleteResponse.StatusCode)
            let! getResponse = client.GetAsync $"/api/todos/{item.Id}"
            Assert.Equal (HttpStatusCode.NotFound, getResponse.StatusCode)
        }

    [<Fact>]
    member _.``DELETE /api/todos/completed removes only completed todos`` () =
        task {
            // Given one completed todo and one active todo
            fixture.CleanDatabase ()
            let completed = todo (Guid.NewGuid ()) "Done task" true
            let active = todo (Guid.NewGuid ()) "Active task" false
            let! _ = postJson "/api/todos" completed
            let! _ = postJson "/api/todos" active

            // When deleting all completed todos
            let! deleteResponse = client.DeleteAsync "/api/todos/completed"

            // Then only the completed todo is removed and the active one remains
            Assert.Equal (HttpStatusCode.NoContent, deleteResponse.StatusCode)
            let! response = client.GetAsync "/api/todos"
            let! body = response.Content.ReadAsStringAsync ()

            match Decode.fromString<Todo list> body with
            | Ok items ->
                Assert.Equal (1, List.length items)
                Assert.Equal (active.Id, items[0].Id)
            | Error err -> Assert.True (false, err)
        }
