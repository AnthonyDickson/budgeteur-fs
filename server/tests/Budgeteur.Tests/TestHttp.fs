namespace Budgeteur.Tests

open System.Net.Http
open System.Text
open Budgeteur.Shared.Coders

/// JSON helpers for driving the test HTTP client. Each builds a UTF-8 JSON body
/// from the given value and sends it with the corresponding HTTP method.
module TestHttp =

    let postJson (client : HttpClient) (url : string) (value : 'T) =
        let json = Encode.toStringAuto value
        let content = new StringContent (json, Encoding.UTF8, "application/json")
        client.PostAsync (url, content)

    let putJson (client : HttpClient) (url : string) (value : 'T) =
        let json = Encode.toStringAuto value
        let content = new StringContent (json, Encoding.UTF8, "application/json")
        client.PutAsync (url, content)

    let patchJson (client : HttpClient) (url : string) (value : 'T) =
        let json = Encode.toStringAuto value
        let content = new StringContent (json, Encoding.UTF8, "application/json")
        client.PatchAsync (url, content)

/// Assertions for user scoping: every query must filter by the `sub` claim.
module Scoping =
    open System.Net
    open Expecto

    /// Assert that `otherUser` can neither read, list, replace, nor delete the item at `itemPath`,
    /// and that `owner` can still read it afterwards.
    let expectHiddenFrom
        (owner : HttpClient)
        (otherUser : HttpClient)
        (listPath : string)
        (itemPath : string)
        (replacement : 'T)
        =
        async {
            let! read = otherUser.GetAsync itemPath |> Async.AwaitTask
            Expect.equal read.StatusCode HttpStatusCode.NotFound "another user's read should be 404"

            let! list = otherUser.GetStringAsync listPath |> Async.AwaitTask
            Expect.equal list "[]" "another user's list should be empty"

            let! update = TestHttp.putJson otherUser itemPath replacement |> Async.AwaitTask
            Expect.equal update.StatusCode HttpStatusCode.NotFound "another user's update should be 404"

            let! delete = otherUser.DeleteAsync itemPath |> Async.AwaitTask
            Expect.equal delete.StatusCode HttpStatusCode.NotFound "another user's delete should be 404"

            let! stillThere = owner.GetAsync itemPath |> Async.AwaitTask
            Expect.equal stillThere.StatusCode HttpStatusCode.OK "the owner should still see the item"
        }
