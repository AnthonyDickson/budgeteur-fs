namespace Budgeteur.Tests

open System
open Expecto

open Budgeteur.Domain.Money
open Budgeteur.Domain.Transaction
open Budgeteur.Domain.Vectoriser

module VectoriserTests =
    let private account = Guid.NewGuid ()

    let private transaction (description : string) (amount : decimal) = {
        Id = Guid.NewGuid ()
        Amount = Money.create amount
        Description = TransactionDescription.unsafeFromString description
        Date = DateOnly (2026, 1, 1)
        AccountId = Some account
    }

    /// The transaction's non-zero features by block and term.
    let private featuresOf vectoriser transaction =
        let features = Vectoriser.features vectoriser
        let vector = Vectoriser.transform vectoriser transaction

        Array.zip vector.Columns vector.Values
        |> Array.map (fun (column, value) -> features[column], value)
        |> Map.ofArray

    let private termsIn block features =
        features
        |> Map.keys
        |> Seq.filter (fun feature -> feature.Block = block)
        |> Seq.map (fun feature -> feature.Term)
        |> Set.ofSeq

    let private blockNorm block features =
        features
        |> Map.toList
        |> List.filter (fun (feature, _) -> feature.Block = block)
        |> List.sumBy (fun (_, value) -> value * value)
        |> sqrt

    let private fitOn transactions = Vectoriser.fit transactions

    [<Tests>]
    let tests =
        testList "Vectoriser" [
            testCase
                "normalise folds case, replaces digit runs, and collapses \
                      whitespace"
            <| fun () ->
                Expect.equal
                    (Vectoriser.normalise "  Pak'n Save  4021\t12 café ")
                    "PAK'N SAVE # # CAFÉ"
                    "normalised description"

            testCase "n-grams are 3 to 5 characters within padded words"
            <| fun () ->
                let row = transaction "ab cdef" -1m
                let features = featuresOf (fitOn [ row ]) row

                Expect.equal
                    (termsIn Block.Chars features)
                    (set [
                        " AB"
                        "AB "
                        " AB "
                        " CD"
                        "CDE"
                        "DEF"
                        "EF "
                        " CDE"
                        "CDEF"
                        "DEF "
                        " CDEF"
                        "CDEF "
                    ])
                    "a padded word no longer than n is one n-gram"

            testCase "words are the normalised description's tokens"
            <| fun () ->
                let row = transaction "pos w/d Fresh  Mart 123" -1m
                let features = featuresOf (fitOn [ row ]) row

                Expect.equal
                    (termsIn Block.Words features)
                    (set [ "POS"; "W/D"; "FRESH"; "MART"; "#" ])
                    "word tokens"

            testCase "IDF is smoothed and each text block has unit length"
            <| fun () ->
                let common = transaction "shop alpha" -1m
                let rare = transaction "shop beta" -1m
                let vectoriser = fitOn [ common; rare; transaction "alpha" -1m ]
                let features = featuresOf vectoriser common

                // SHOP is in 2 of 3 documents and ALPHA in 2 of 3, so they
                // weigh the same; in `rare`, BETA (1 of 3) outweighs SHOP.
                let word term =
                    features[{ Block = Block.Words; Term = term }]

                Expect.floatClose
                    Accuracy.veryHigh
                    (word "SHOP")
                    (word "ALPHA")
                    "same df"

                let rareFeatures = featuresOf vectoriser rare

                let rareWord term =
                    rareFeatures[{ Block = Block.Words; Term = term }]

                let idf df = log (4.0 / (1.0 + df)) + 1.0

                Expect.floatClose
                    Accuracy.veryHigh
                    (rareWord "BETA" / rareWord "SHOP")
                    (idf 1.0 / idf 2.0)
                    "values are in the ratio of their IDF weights"

                for block in [ Block.Chars; Block.Words ] do
                    Expect.floatClose
                        Accuracy.veryHigh
                        (blockNorm block features)
                        1.0
                        $"%A{block} has unit length"

            testCase "the amount is its sign and its sign with a log2 bucket"
            <| fun () ->
                let amounts = [ -82.44m; 0m; 1m; 1500m ]
                let rows = amounts |> List.map (transaction "shop")
                let vectoriser = fitOn rows

                let amountTerms row =
                    featuresOf vectoriser row |> termsIn Block.Amount

                Expect.equal
                    (rows |> List.map amountTerms)
                    [
                        set [ "sign_-"; "bucket_-6" ]
                        set [ "sign_+"; "bucket_+0" ]
                        set [ "sign_+"; "bucket_+1" ]
                        set [ "sign_+"; "bucket_+10" ]
                    ]
                    "sign and bucket, with zero counted as positive"

            testCase "the account is a category"
            <| fun () ->
                let row = transaction "shop" -1m

                let noAccount = {
                    transaction "shop" -1m with
                        AccountId = None
                }

                let vectoriser = fitOn [ row; noAccount ]

                Expect.equal
                    (featuresOf vectoriser row |> termsIn Block.Account)
                    (set [ string account ])
                    "the account's id"

                Expect.equal
                    (featuresOf vectoriser noAccount |> termsIn Block.Account)
                    (set [ "" ])
                    "no account is a category of its own"

            testCase "terms and categories outside the training set are ignored"
            <| fun () ->
                let vectoriser = fitOn [ transaction "shop alpha" -10m ]

                let unseen = {
                    transaction "shop gamma" 10m with
                        AccountId = Some (Guid.NewGuid ())
                }

                let features = featuresOf vectoriser unseen

                Expect.equal
                    (termsIn Block.Words features)
                    (set [ "SHOP" ])
                    "only the known word"

                Expect.isEmpty
                    (termsIn Block.Amount features)
                    "unknown amount categories"

                Expect.isEmpty
                    (termsIn Block.Account features)
                    "unknown account"

                Expect.floatClose
                    Accuracy.veryHigh
                    (blockNorm Block.Words features)
                    1.0
                    "the known terms have unit length"

            testCase "columns do not depend on the order of the training set"
            <| fun () ->
                let rows = [
                    transaction "fresh mart" -20m
                    transaction "harbour cafe" -8.5m
                    transaction "salary" 2000m
                ]

                Expect.equal
                    (Vectoriser.features (fitOn rows))
                    (Vectoriser.features (fitOn (List.rev rows)))
                    "same columns in the same order"
        ]
