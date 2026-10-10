namespace Budgeteur.Tests.Tags

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    /// Fill the Oxpecker routef `{%O:guid}` placeholder in an item path with a concrete id.
    let private routefPath (path : string) (id : Guid) =
        path.Replace ("{%O:guid}", id.ToString ())

    let private createRequest (name : string) (kind : string) : CreateTag.CreateTagRequest = {
        Name = name
        Color = "#22C55E"
        Kind = kind
    }

    let private updateRequest (name : string) (kind : string) : UpdateTag.UpdateTagRequest = {
        Name = name
        Color = "#22C55E"
        Kind = kind
    }

    let private newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTags)

    /// Fail the test with the decoder's message rather than an opaque null.
    let private decodeBody<'T> (response : HttpResponseMessage) : Async<'T> =
        async {
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

            match Decode.fromStringAuto<'T> body with
            | Ok value -> return value
            | Error error -> return failtest error
        }

    [<Tests>]
    let tests =
        testList "Tags" [
            testCaseAsync "the kind is stored on create and replaced on update"
            <| async {
                use app = newApp ()

                let! created =
                    TestHttp.postJson app.Client CreateTag.Path (createRequest "Salary" "Income")
                    |> Async.AwaitTask

                Expect.equal created.StatusCode HttpStatusCode.Created "create should return 201"
                let! created = decodeBody<TagResponse> created
                Expect.equal created.Kind "Income" "create should return the kind"

                let! updated =
                    TestHttp.putJson
                        app.Client
                        (routefPath UpdateTag.Path created.Id)
                        (updateRequest "Salary" "Expense")
                    |> Async.AwaitTask

                Expect.equal updated.StatusCode HttpStatusCode.OK "update should return 200"

                let! read =
                    app.Client.GetAsync (routefPath ReadTag.Path created.Id) |> Async.AwaitTask

                let! read = decodeBody<TagResponse> read
                Expect.equal read.Kind "Expense" "the stored kind should be the updated one"
            }

            testCaseAsync "a tag is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! created =
                    TestHttp.postJson app.Client CreateTag.Path (createRequest "Salary" "Income")
                    |> Async.AwaitTask

                let! created = decodeBody<TagResponse> created

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllTags.Path
                        (routefPath ReadTag.Path created.Id)
                        (updateRequest "Hijacked" "Expense")
            }

            testCaseAsync "an unknown kind is reported as a bad request"
            <| async {
                use app = newApp ()

                let! response =
                    TestHttp.postJson app.Client CreateTag.Path (createRequest "Transfers" "Transfer")
                    |> Async.AwaitTask

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "an unknown kind should be rejected"

                let! tags = app.Client.GetAsync ReadAllTags.Path |> Async.AwaitTask
                let! tags = decodeBody<TagResponse list> tags
                Expect.isEmpty tags "a rejected tag should not be stored"
            }
        ]
