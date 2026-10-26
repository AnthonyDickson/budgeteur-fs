#!/usr/bin/env -S dotnet fsi

// Time smart tagging fits on the exported labels and on training sets several
// times their size, for decision 5 in docs/smart-tagging.md. Not run in CI: it
// reads the real data `just ml-export` writes to the gitignored ml/data/.
//
// Usage: dotnet fsi smart-tagging-scaling.fsx <transactions.csv>
//
// A larger training set is copies of the export, each with its own accounts
// and transaction ids. The fit merges identical rows, so copies with the same
// accounts would cost nothing; with their own, each copy repeats rows as often
// as the export does. The text vocabulary stays the export's, where real
// growth would add to it about as the square root of the labels.

#r "nuget: System.Numerics.Tensors, 10.0.12"
#r "../src/Budgeteur/bin/Release/net10.0/linux-x64/Budgeteur.dll"

open System
open System.Diagnostics
open System.IO

open Budgeteur.Domain.Categorisation
open Budgeteur.Domain.Money
open Budgeteur.Domain.SmartTagging
open Budgeteur.Domain.Transaction
open Budgeteur.Domain.Vectoriser
open Budgeteur.Feature.Import

let path =
    match fsi.CommandLineArgs |> Array.tail with
    | [| path |] -> path
    | _ ->
        eprintfn "Usage: dotnet fsi smart-tagging-scaling.fsx <transactions.csv>"
        exit 1

/// Copies of the export in each training set.
let copies = [ 1; 5; 10 ]

/// Timed fits per size, after one untimed fit to warm up the JIT.
let repeats = 5

let fieldsOrFail (line: CsvLine) =
    match Csv.fields line.Text with
    | Ok fields -> fields
    | Error error -> failwithf "line %i: %s" line.Number error

let labels =
    match File.ReadAllText path |> Csv.lines |> List.map fieldsOrFail with
    | header :: rows ->
        rows
        |> List.choose (fun fields ->
            let row = List.zip header fields |> Map.ofList

            let source () =
                match Source.parse row["source"] with
                | Ok source -> source
                | Error error -> failwith error

            let categorisation =
                match row["kind"] with
                | "Tagged" -> Some(Categorisation.Tagged(Guid row["tag_id"], source ()))
                | "Transfer" -> Some(Categorisation.Transfer(source ()))
                | _ -> None

            let transaction =
                {
                    Id = Guid row["id"]
                    Amount = Money.create (decimal row["amount"])
                    Description =
                        match TransactionDescription.create row["description"] with
                        | Ok description -> description
                        | Error error -> failwithf "%A" error
                    Date = DateOnly.Parse row["date"]
                    AccountId =
                        match row["account_id"] with
                        | "" -> None
                        | id -> Some(Guid id)
                }

            categorisation |> Option.bind (Label.ofCategorisation transaction))
        |> Array.ofList
    | [] -> failwith "the export is empty"

/// An id for the copy of an export's id: the copy number in its last bytes.
let copyId (copy: int) (id: Guid) =
    let bytes = id.ToByteArray()
    BitConverter.GetBytes copy |> Array.iteri (fun i b -> bytes[12 + i] <- b)
    Guid bytes

/// The export's labels repeated `count` times, each copy with its own ids.
let copied count =
    [
        for copy in 0 .. count - 1 do
            for label in labels ->
                { label with
                    Transaction =
                        { label.Transaction with
                            Id = copyId copy label.Transaction.Id
                            AccountId = label.Transaction.AccountId |> Option.map (copyId copy)
                        }
                }
    ]

printfn "%i labels in the export" labels.Length

printfn "| Labels | Classes | Features | Median fit (ms) | Slowest (ms) |"
printfn "| -----: | ------: | -------: | --------------: | -----------: |"

let trainingSets = copies |> List.map copied

for training in trainingSets do
    Model.fit training |> ignore

    let times =
        List.init repeats (fun _ ->
            let watch = Stopwatch.StartNew()
            Model.fit training |> ignore
            watch.Elapsed.TotalMilliseconds)
        |> List.sort

    let classes = training |> List.distinctBy _.Class |> List.length

    let features =
        Vectoriser.fit (training |> List.map _.Transaction)
        |> Vectoriser.features
        |> Array.length

    printfn
        "| %6i | %7i | %8i | %15.0f | %12.0f |"
        training.Length
        classes
        features
        times[repeats / 2]
        (List.last times)
