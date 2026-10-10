namespace Budgeteur.Tests.Tags

module EndpointTests =
    open System.Net
    open Expecto

    open Budgeteur.Feature.Tag
    open Budgeteur.Tests

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
                let! created = TestHttp.readJson<TagResponse> created
                Expect.equal created.Kind "Income" "create should return the kind"

                let! updated =
                    TestHttp.putJson
                        app.Client
                        (TestHttp.itemPath UpdateTag.Path created.Id)
                        (updateRequest "Salary" "Expense")
                    |> Async.AwaitTask

                Expect.equal updated.StatusCode HttpStatusCode.OK "update should return 200"

                let! read =
                    app.Client.GetAsync (TestHttp.itemPath ReadTag.Path created.Id)
                    |> Async.AwaitTask

                let! read = TestHttp.readJson<TagResponse> read
                Expect.equal read.Kind "Expense" "the stored kind should be the updated one"
            }

            testCaseAsync "a tag is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! id = Seed.tag app.Client "Salary" "Income"

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllTags.Path
                        (TestHttp.itemPath ReadTag.Path id)
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
                let! tags = TestHttp.readJson<TagResponse list> tags
                Expect.isEmpty tags "a rejected tag should not be stored"
            }
        ]
