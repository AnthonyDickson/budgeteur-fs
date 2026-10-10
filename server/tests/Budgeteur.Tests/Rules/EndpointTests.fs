namespace Budgeteur.Tests.Rules

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Tag
    open Budgeteur.Shared.Coders
    open Budgeteur.Tests

    /// Fill the Oxpecker routef `{%O:guid}` placeholder in an item path with a concrete id.
    let private routefPath (path : string) (id : Guid) =
        path.Replace ("{%O:guid}", id.ToString ())

    let private newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTags |> TestAppConfig.withRules)

    /// Fail the test with the decoder's message rather than an opaque null.
    let private decodeBody<'T> (response : HttpResponseMessage) : Async<'T> =
        async {
            let! body = response.Content.ReadAsStringAsync () |> Async.AwaitTask

            match Decode.fromStringAuto<'T> body with
            | Ok value -> return value
            | Error error -> return failtest error
        }

    let private createTag (client : HttpClient) (name : string) =
        async {
            let request : CreateTag.CreateTagRequest = {
                Name = name
                Color = "#22C55E"
                Kind = "Expense"
            }

            let! response = TestHttp.postJson client CreateTag.Path request |> Async.AwaitTask
            let! tag = decodeBody<TagResponse> response
            return tag.Id
        }

    let private createRule (client : HttpClient) (pattern : string) (tagId : Guid) =
        let request : CreateRule.CreateRuleRequest = { Pattern = pattern; TagId = tagId }
        TestHttp.postJson client CreateRule.Path request |> Async.AwaitTask

    [<Tests>]
    let tests =
        testList "Rules" [
            testCaseAsync "a rule is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! tagId = createTag app.Client "Coffee"
                let! created = createRule app.Client "STARBUCKS" tagId
                let! created = decodeBody<RuleResponse> created

                // A body that is valid for the other user, so only the rule's owner decides the outcome.
                let! otherTagId = createTag otherUser "Coffee"

                let replacement : UpdateRule.UpdateRuleRequest = {
                    Pattern = "HIJACKED"
                    TagId = otherTagId
                }

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllRules.Path
                        (routefPath ReadRule.Path created.Id)
                        replacement
            }

            testCaseAsync "a rule cannot use another user's tag"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! tagId = createTag app.Client "Coffee"
                let! response = createRule otherUser "STARBUCKS" tagId

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "another user's tag should be rejected"
            }
        ]
