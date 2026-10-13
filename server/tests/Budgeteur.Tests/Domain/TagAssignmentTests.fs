namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.TagAssignment

module TagAssignmentTests =
    let private tagA = Guid.NewGuid ()
    let private tagB = Guid.NewGuid ()

    let private manual tagId =
        Some (TagAssignment.Tagged (tagId, TagSource.Manual))

    let private byRule tagId =
        Some (TagAssignment.Tagged (tagId, TagSource.Rule))

    let private dismissed = Some TagAssignment.Dismissed

    [<Tests>]
    let tests =
        testList "TagAssignment" [
            testCase "onCreate makes a tag manual"
            <| fun () ->
                let onCreate = TagAssignment.onCreate
                Expect.equal (onCreate (Some tagA)) (manual tagA) "tagged"
                Expect.equal (onCreate None) None "untagged"

            testCase "onUpdate keeps the source only when the tag is unchanged"
            <| fun () ->
                let onUpdate = TagAssignment.onUpdate false
                let expect = Expect.equal

                expect (onUpdate (Some tagA) (byRule tagA)) (byRule tagA) "same"
                expect (onUpdate (Some tagB) (byRule tagA)) (manual tagB) "new"
                expect (onUpdate (Some tagA) None) (manual tagA) "untagged"
                expect (onUpdate None (byRule tagA)) None "clear rule tag"
                expect (onUpdate None (manual tagA)) None "clear manual tag"

            testCase "onUpdate keeps a dismissal until the user picks a tag"
            <| fun () ->
                let onUpdate = TagAssignment.onUpdate false
                let expect = Expect.equal

                expect (onUpdate None dismissed) dismissed "no tag"
                expect (onUpdate (Some tagA) dismissed) (manual tagA) "tag"

            testCase "onUpdate removes a transfer's assignment"
            <| fun () ->
                let onUpdate = TagAssignment.onUpdate true
                let expect = Expect.equal

                expect (onUpdate None (manual tagA)) None "manual tag"
                expect (onUpdate None (byRule tagA)) None "rule tag"
                expect (onUpdate None dismissed) None "dismissal"

            testCase "a transfer cannot have a tag"
            <| fun () ->
                let require = TagAssignment.requireNoTagOnTransfer
                Expect.isError (require true (Some tagA)) "tagged transfer"
                Expect.isOk (require true None) "untagged transfer"
                Expect.isOk (require false (Some tagA)) "tagged transaction"

            testCase "tagUntagged only tags untagged transactions"
            <| fun () ->
                let tagUntagged = TagAssignment.tagUntagged
                let expect = Expect.equal

                expect (tagUntagged (Some tagA) None) (byRule tagA) "untagged"
                expect (tagUntagged None None) None "no winner"

                expect
                    (tagUntagged (Some tagB) (byRule tagA))
                    (byRule tagA)
                    "rule"

                expect
                    (tagUntagged (Some tagB) (manual tagA))
                    (manual tagA)
                    "manual"

                expect (tagUntagged (Some tagA) dismissed) dismissed "dismissed"

            testCase "retag recomputes everything but manual decisions"
            <| fun () ->
                let retag = TagAssignment.retag
                let expect = Expect.equal

                expect (retag (Some tagA) None) (byRule tagA) "untagged"
                expect (retag (Some tagB) (byRule tagA)) (byRule tagB) "changed"
                expect (retag None (byRule tagA)) None "cleared"
                expect (retag (Some tagB) (manual tagA)) (manual tagA) "manual"

                expect
                    (retag None (manual tagA))
                    (manual tagA)
                    "manual, no winner"

                expect (retag (Some tagA) dismissed) dismissed "dismissed"
        ]
