namespace Budgeteur.Tests.OpenApi

module DocumentTests =
    open System.Text.Json
    open Expecto
    open Microsoft.AspNetCore.Builder
    open Microsoft.AspNetCore.TestHost
    open Microsoft.Extensions.DependencyInjection
    open Oxpecker

    open Budgeteur.Data.Db
    open Budgeteur.Feature.Status
    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Config
    open Budgeteur.Shared.OpenApi

    /// The OpenAPI document for the status endpoint and the tag slice, routed
    /// as the server routes them. Generating it never touches the database.
    let private document () =
        task {
            let builder = WebApplication.CreateBuilder ()
            builder.WebHost.UseTestServer () |> ignore
            builder.Services.AddRouting().AddOxpecker() |> ignore

            OpenApi.configureServices builder.Services {
                ClientId = "scalar-docs"
                AuthorizationUrl = "https://provider.test/authorize"
                TokenUrl = "https://provider.test/token"
            }

            use app = builder.Build ()
            let queryContext = QueryContextFactory.Create "Data Source=unused"

            let endpoints = [
                GET [
                    GetStatus.endpoint
                        "Data Source=unused"
                        "Development"
                        System.DateTime.UtcNow
                ]
                yield!
                    TagEndpoints.all queryContext |> List.map Auth.authenticated
            ]

            app.UseRouting().UseOxpecker endpoints |> ignore
            OpenApi.mapEndpoints app "scalar-docs"
            do! app.StartAsync ()

            let! body = app.GetTestClient().GetStringAsync "/openapi/v1.json"
            do! app.StopAsync ()
            return JsonDocument.Parse(body).RootElement
        }
        |> Async.AwaitTask

    let private at (keys : string list) (element : JsonElement) =
        keys
        |> List.fold (fun (e : JsonElement) key -> e.GetProperty key) element

    let private strings (element : JsonElement) = [
        for item in element.EnumerateArray () -> item.GetString ()
    ]

    [<Tests>]
    let tests =
        testList "OpenAPI document" [
            testCaseAsync "only authenticated operations declare security"
            <| async {
                let! doc = document ()

                let found, _ = doc.TryGetProperty "security"
                Expect.isFalse found "no document-level security"

                let found, _ =
                    (at [ "paths"; GetStatus.Path; "get" ] doc).TryGetProperty
                        "security"

                Expect.isFalse found "the status endpoint is open"

                let security =
                    at [ "paths"; CreateTag.Path; "post"; "security" ] doc

                Expect.equal
                    [
                        for requirement in security.EnumerateArray () do
                            for scheme in requirement.EnumerateObject () ->
                                scheme.Name
                    ]
                    [ "scalarOAuth2" ]
                    "tag endpoints require the OAuth scheme"
            }

            testCaseAsync "required fields use the serialised names"
            <| async {
                let! doc = document ()
                let schemas = at [ "components"; "schemas" ] doc

                Expect.equal
                    (strings (at [ "CreateTagRequest"; "required" ] schemas))
                    [ "name"; "color"; "kind" ]
                    "request fields"

                Expect.equal
                    (strings (at [ "ApiError"; "required" ] schemas))
                    [ "error"; "details"; "requestId" ]
                    "option fields are not required"
            }

            testCaseAsync "the tag name's length follows the domain"
            <| async {
                let! doc = document ()

                let name =
                    at
                        [
                            "components"
                            "schemas"
                            "CreateTagRequest"
                            "properties"
                            "name"
                        ]
                        doc

                Expect.equal
                    ((name.GetProperty "maxLength").GetInt32())
                    Budgeteur.Domain.Tag.TagName.MaxLength
                    "max length"
            }
        ]
