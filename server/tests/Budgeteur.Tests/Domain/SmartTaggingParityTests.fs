namespace Budgeteur.Tests

open System
open System.IO
open Expecto

open Budgeteur.Domain.Money
open Budgeteur.Domain.Transaction
open Budgeteur.Domain.Vectoriser
open Budgeteur.Feature.Import

/// Parity with scikit-learn on the fixtures `just ml-parity` writes, see
/// decision 10 in docs/smart-tagging.md.
module SmartTaggingParityTests =
    /// How far a feature value may differ from scikit-learn's.
    let private featureTolerance = 1e-12

    let private read (name : string) : Map<string, string> list =
        let path =
            Path.Combine (
                AppContext.BaseDirectory,
                "Domain",
                "Fixtures",
                "SmartTagging",
                $"{name}.csv"
            )

        let rows =
            File.ReadAllText path
            |> Csv.lines
            |> List.map (fun line ->
                match Csv.fields line.Text with
                | Ok fields -> fields
                | Error error ->
                    failtestf "%s line %i: %s" name line.Number error)

        match rows with
        | header :: rows -> rows |> List.map (List.zip header >> Map.ofList)
        | [] -> failtestf "%s is empty" name

    /// A fixture transaction, with its label and weight, if any.
    type private Row = {
        Id : string
        Transaction : Transaction
        Label : string option
        Weight : float
    }

    let private accounts =
        read "transactions"
        |> List.map (fun row -> row["account_id"])
        |> List.distinct
        |> List.mapi (fun index name ->
            name, Guid (sprintf "00000000-0000-0000-0000-%012i" (index + 1)))
        |> Map.ofList

    let private accountName =
        accounts
        |> Map.toList
        |> List.map (fun (name, id) -> string id, name)
        |> Map.ofList

    let private rows =
        read "transactions"
        |> List.map (fun row -> {
            Id = row["id"]
            Transaction = {
                Id = Guid.NewGuid ()
                Amount = Money.create (decimal row["amount"])
                Description =
                    TransactionDescription.unsafeFromString row["description"]
                Date = DateOnly (2026, 1, 1)
                AccountId = Some accounts[row["account_id"]]
            }
            Label = if row["label"] = "" then None else Some row["label"]
            Weight = float row["weight"]
        })

    let private labelled = rows |> List.filter (fun row -> row.Label.IsSome)

    let private blockName (block : Block) =
        match block with
        | Block.Chars -> "chars"
        | Block.Words -> "words"
        | Block.Amount -> "amount"
        | Block.Account -> "account"

    /// A feature as the fixture names it: accounts by name rather than id.
    let private featureName (feature : Feature) =
        let term =
            match feature.Block with
            | Block.Account -> accountName[feature.Term]
            | Block.Chars
            | Block.Words
            | Block.Amount -> feature.Term

        blockName feature.Block, term

    [<Tests>]
    let tests =
        testList "Smart tagging parity" [
            testCase "features match scikit-learn's"
            <| fun () ->
                let vectoriser =
                    Vectoriser.fit (labelled |> List.map _.Transaction)

                let features = Vectoriser.features vectoriser

                let byId =
                    rows |> List.map (fun row -> row.Id, row) |> Map.ofList

                let expected =
                    read "features" |> List.groupBy (fun row -> row["id"])

                Expect.isNonEmpty expected "the fixture has features"

                for id, expectedRows in expected do
                    let vector =
                        Vectoriser.transform vectoriser byId[id].Transaction

                    let actual =
                        Array.zip vector.Columns vector.Values
                        |> Array.map (fun (column, value) ->
                            featureName features[column], value)
                        |> Map.ofArray

                    let expected =
                        expectedRows
                        |> List.map (fun row ->
                            (row["block"], row["term"]), float row["value"])
                        |> Map.ofList

                    Expect.equal
                        (Map.keys actual |> Set.ofSeq)
                        (Map.keys expected |> Set.ofSeq)
                        $"{id}: the same non-zero features"

                    for KeyValue (feature, value) in expected do
                        Expect.floatClose
                            {
                                absolute = featureTolerance
                                relative = 0.0
                            }
                            actual[feature]
                            value
                            $"{id}: %A{feature}"
        ]
