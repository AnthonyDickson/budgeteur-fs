namespace Budgeteur.Tests.Rules

module EndpointTests =
    open System
    open System.Net
    open System.Net.Http
    open Expecto

    open Budgeteur.Feature.Rule
    open Budgeteur.Tests

    let private newApp () =
        TestApp.create (TestAppConfig.empty |> TestAppConfig.withTags |> TestAppConfig.withRules)

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

                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! created = createRule app.Client "STARBUCKS" tagId
                let! created = TestHttp.readJson<RuleResponse> created

                // A body that is valid for the other user, so only the rule's owner decides the outcome.
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

            testCaseAsync "a rule cannot use another user's tag"
            <| async {
                use app = newApp ()
                use otherUser = app.ClientForUser "other-user"

                let! tagId = Seed.tag app.Client "Coffee" "Expense"
                let! response = createRule otherUser "STARBUCKS" tagId

                Expect.equal response.StatusCode HttpStatusCode.BadRequest "another user's tag should be rejected"
            }
        ]
