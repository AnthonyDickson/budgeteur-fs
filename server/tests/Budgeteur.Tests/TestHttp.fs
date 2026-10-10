namespace Budgeteur.Tests

open System.Net.Http
open System.Text
open Expecto

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

    /// Fill the Oxpecker routef `{%O:guid}` placeholder in an item path with a concrete id.
    let itemPath (path : string) (id : System.Guid) =
        path.Replace ("{%O:guid}", id.ToString ())

    /// Decode a JSON response body, failing the test with the decoder's message rather than an
    /// opaque null.
    let readJson<'T> (response : HttpResponseMessage) : Async<'T> =
        async {
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

            match Decode.fromStringAuto<'T> body with
            | Ok value -> return value
            | Error error -> return failtest error
        }

/// Data that tests in several slices need to set up.
module Seed =
    open System
    open System.Net

    open Budgeteur.Feature.Tag

    /// Create a tag and return its server-assigned id.
    let tag (client : HttpClient) (name : string) (kind : string) : Async<Guid> =
        async {
            let request : CreateTag.CreateTagRequest = {
                Name = name
                Color = "#22C55E"
                Kind = kind
            }

            let! response = TestHttp.postJson client CreateTag.Path request |> Async.AwaitTask
            Expect.equal response.StatusCode HttpStatusCode.Created "creating a tag should return 201"
            let! tag = TestHttp.readJson<TagResponse> response
            return tag.Id
        }

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
