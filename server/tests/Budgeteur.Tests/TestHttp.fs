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
