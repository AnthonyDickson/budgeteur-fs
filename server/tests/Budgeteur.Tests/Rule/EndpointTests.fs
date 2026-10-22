namespace Budgeteur.Tests.Rule

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Rule
    open Budgeteur.Feature.Tag
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
            Target = "Tag"
            TagId = Some tagId
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
                    Target = "Tag"
                    TagId = Some otherTagId
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
                    Target = "Tag"
                    TagId = Some tagId
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

            testCaseAsync
                "a tag rule needs a tag id and a transfer rule rejects one"
            <| async {
                use app = newApp ()
                let! tagId = Seed.tag app.Client "Coffee" "Expense"

                let post target tagId =
                    TestHttp.postJson
                        app.Client
                        CreateRule.Path
                        ({
                            Pattern = "STARBUCKS"
                            Target = target
                            TagId = tagId
                        }
                        : CreateRule.CreateRuleRequest)
                    |> Async.AwaitTask

                for target, tagId, label in
                    [
                        "Tag", None, "a tag rule without a tag"
                        "Transfer", Some tagId, "a transfer rule with a tag"
                        "Dismissed", None, "an unknown target"
                    ] do
                    let! response = post target tagId

                    Expect.equal
                        response.StatusCode
                        HttpStatusCode.BadRequest
                        $"{label} should be rejected"

                let! created = post "Transfer" None

                Expect.equal
                    created.StatusCode
                    HttpStatusCode.Created
                    "a transfer rule without a tag should be created"

                let! created = TestHttp.readJson<RuleResponse> created

                let! read =
                    app.Client.GetAsync (
                        TestHttp.itemPath ReadRule.Path created.Id
                    )
                    |> Async.AwaitTask

                let! read = TestHttp.readJson<RuleResponse> read

                Expect.equal
                    (read.Target, read.TagId)
                    ("Transfer", None)
                    "the rule should read back as a transfer rule"
            }

            testCaseAsync
                "deleting a tag deletes its rules but not transfer rules"
            <| async {
                use app = newApp ()
                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! _ = createRule app.Client "STARBUCKS" tagId

                let! _ =
                    TestHttp.postJson
                        app.Client
                        CreateRule.Path
                        ({
                            Pattern = "TO SAVINGS"
                            Target = "Transfer"
                            TagId = None
                        }
                        : CreateRule.CreateRuleRequest)
                    |> Async.AwaitTask

                let! _ =
                    app.Client.DeleteAsync (
                        TestHttp.itemPath DeleteTag.Path tagId
                    )
                    |> Async.AwaitTask

                let! rules =
                    app.Client.GetAsync ReadAllRules.Path |> Async.AwaitTask

                let! rules = TestHttp.readJson<RuleResponse list> rules

                Expect.equal
                    (rules |> List.map _.Pattern)
                    [ "TO SAVINGS" ]
                    "only the transfer rule should remain"
            }
        ]
