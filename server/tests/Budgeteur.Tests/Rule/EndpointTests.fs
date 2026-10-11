namespace Budgeteur.Tests.Rule

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Rule
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (
            TestAppConfig.empty
            |> TestAppConfig.withTags
            |> TestAppConfig.withRules
        )

    let private createRule
        (client : HttpClient)
        (pattern : string)
        (tagId : Guid)
        =
        let request : CreateRule.CreateRuleRequest = {
            Pattern = pattern
            TagId = tagId
        }

        TestHttp.postJson client CreateRule.Path request |> Async.AwaitTask

    [<Tests>]
    let tests =
        testList "Rules" [
            testCaseAsync "a rule is scoped to the owning user"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! created = createRule app.Client "STARBUCKS" tagId
                let! created = TestHttp.readJson<RuleResponse> created

                // A body that is valid for the other user, so only the rule's
                // owner decides the outcome.
                let! otherTagId = Seed.tag otherUser "Coffee" "Expense"

                let replacement : UpdateRule.UpdateRuleRequest = {
                    Pattern = "HIJACKED"
                    TagId = otherTagId
                }

                do!
                    Scoping.expectHiddenFrom
                        app.Client
                        otherUser
                        ReadAllRules.Path
                        (TestHttp.itemPath ReadRule.Path created.Id)
                        replacement
            }

            testCaseAsync
                "a pattern is unique per user, ignoring case, whatever its tag"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! coffee = Seed.tag app.Client "Coffee" "Expense"
                let! dining = Seed.tag app.Client "Dining" "Expense"
                let! _ = createRule app.Client "STARBUCKS" coffee
                let! _ = createRule app.Client "CAFÉ" coffee

                // NOCASE in the schema folds ASCII only, so "café" checks that
                // the server compares patterns itself.
                for pattern in [ "starbucks"; "café" ] do
                    let! duplicate = createRule app.Client pattern dining

                    Expect.equal
                        duplicate.StatusCode
                        HttpStatusCode.BadRequest
                        $"'{pattern}' should collide under another tag"

                let! otherTag = Seed.tag otherUser "Coffee" "Expense"
                let! otherUsers = createRule otherUser "STARBUCKS" otherTag

                Expect.equal
                    otherUsers.StatusCode
                    HttpStatusCode.Created
                    "another user's pattern should not collide"
            }

            testCaseAsync
                "an update may keep its own pattern but not take another's"
            <| async {
                use app = newApp ()

                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! _ = createRule app.Client "STARBUCKS" tagId
                let! created = createRule app.Client "MUFFIN BREAK" tagId
                let! created = TestHttp.readJson<RuleResponse> created
                let path = TestHttp.itemPath UpdateRule.Path created.Id

                let update pattern : UpdateRule.UpdateRuleRequest = {
                    Pattern = pattern
                    TagId = tagId
                }

                let! kept =
                    TestHttp.putJson app.Client path (update "Muffin Break")
                    |> Async.AwaitTask

                Expect.equal
                    kept.StatusCode
                    HttpStatusCode.OK
                    "the rule's own pattern should not collide"

                let! taken =
                    TestHttp.putJson app.Client path (update "Starbucks")
                    |> Async.AwaitTask

                Expect.equal
                    taken.StatusCode
                    HttpStatusCode.BadRequest
                    "another rule's pattern should collide"
            }

            testCaseAsync "a rule cannot use another user's tag"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! response = createRule otherUser "STARBUCKS" tagId

                Expect.equal
                    response.StatusCode
                    HttpStatusCode.BadRequest
                    "another user's tag should be rejected"
            }
        ]
