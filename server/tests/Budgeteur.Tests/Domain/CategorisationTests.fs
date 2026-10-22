namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.Categorisation

module CategorisationTests =
    let private tagA = Guid.NewGuid ()
    let private tagB = Guid.NewGuid ()

    let private manual tagId =
        Some (Categorisation.Tagged (tagId, Source.Manual))

    let private byRule tagId =
        Some (Categorisation.Tagged (tagId, Source.Rule))

    let private dismissed = Some Categorisation.Dismissed

    let private transfer = Some (Categorisation.Transfer Source.Manual)

    let private accepted tagId =
        Some (Categorisation.Tagged (tagId, Source.Accepted))

    let private detected = Some (Categorisation.Transfer Source.Detected)

    let private acceptedTransfer =
        Some (Categorisation.Transfer Source.Accepted)

    [<Tests>]
    let tests =
        testList "Categorisation" [
            testCase "onCreate makes a tag manual and a transfer a transfer"
            <| fun () ->
                let onCreate = Categorisation.onCreate
                Expect.equal (onCreate false (Some tagA)) (manual tagA) "tagged"
                Expect.equal (onCreate false None) None "untagged"
                Expect.equal (onCreate true None) transfer "transfer"

            testCase "onUpdate keeps the source only when the tag is unchanged"
            <| fun () ->
                let onUpdate = Categorisation.onUpdate false
                let expect = Expect.equal

                expect (onUpdate (Some tagA) (byRule tagA)) (byRule tagA) "same"
                expect (onUpdate (Some tagB) (byRule tagA)) (manual tagB) "new"
                expect (onUpdate (Some tagA) None) (manual tagA) "untagged"
                expect (onUpdate None (byRule tagA)) None "clear rule tag"
                expect (onUpdate None (manual tagA)) None "clear manual tag"

            testCase "onUpdate keeps a dismissal until the user picks a tag"
            <| fun () ->
                let onUpdate = Categorisation.onUpdate false
                let expect = Expect.equal

                expect (onUpdate None dismissed) dismissed "no tag"
                expect (onUpdate (Some tagA) dismissed) (manual tagA) "tag"

            testCase "onUpdate marks and unmarks a transfer"
            <| fun () ->
                let markTransfer = Categorisation.onUpdate true None
                let onUpdate = Categorisation.onUpdate false
                let expect = Expect.equal

                expect (markTransfer (manual tagA)) transfer "manual tag"
                expect (markTransfer (byRule tagA)) transfer "rule tag"
                expect (markTransfer dismissed) transfer "dismissal"
                expect (markTransfer None) transfer "untagged"
                expect (onUpdate None transfer) None "unmarked, no tag"

                expect
                    (onUpdate (Some tagA) transfer)
                    (manual tagA)
                    "unmarked, tag"

            testCase "onUpdate keeps a transfer's source while it stays one"
            <| fun () ->
                let markTransfer = Categorisation.onUpdate true None
                let expect = Expect.equal

                expect (markTransfer detected) detected "detected"

                expect
                    (markTransfer acceptedTransfer)
                    acceptedTransfer
                    "accepted"

            testCase "a transfer cannot have a tag"
            <| fun () ->
                let require = Categorisation.requireNoTagOnTransfer
                Expect.isError (require true (Some tagA)) "tagged transfer"
                Expect.isOk (require true None) "untagged transfer"
                Expect.isOk (require false (Some tagA)) "tagged transaction"

            testCase "tagUntagged only tags untagged transactions"
            <| fun () ->
                let tagUntagged = Categorisation.tagUntagged
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
                expect (tagUntagged (Some tagA) transfer) transfer "transfer"

            testCase "retag recomputes everything but manual decisions"
            <| fun () ->
                let retag = Categorisation.retag
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
                expect (retag (Some tagA) transfer) transfer "transfer"

            testCase "retag changes nothing whose source is not a rule"
            <| fun () ->
                let retag = Categorisation.retag
                let expect = Expect.equal

                expect (retag (Some tagB) (accepted tagA)) (accepted tagA) "tag"
                expect (retag None (accepted tagA)) (accepted tagA) "no winner"
                expect (retag (Some tagA) detected) detected "detected"

                expect
                    (retag (Some tagA) acceptedTransfer)
                    acceptedTransfer
                    "approved transfer"
        ]
