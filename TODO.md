# TODO

- Add action and dialog for deleting a transaction
- Consider adding a transaction type (debit, credit and transfer) and keep all amounts positive.
  - Avoids the need for a tag for internal transfers, makes transfer filtering a first class feature
  - For Kiwibank statements, transfer type can be derived from corresponding column.
  - Would require auto-tagging feature to also set transaction type to automate setting transfer type.
  - Alternative: Add `is_transfer` flag and keep amounts as positive and negative.
- Kiwibank statements have enough info to auto tag internal transfers without dedicated rule
  - If the both the source and target account numbers are in the user's accounts, then you can tag as an internal transfer.
  - This should only apply on import, manual imports must be manually categorised.
  - May want user setting around which category to use for internal transfer, or hardcode and force user to use it.
  - Initial imports will be missed if the accounts are not added beforehand
- Cull unnecessary tests
- Fix E2E tests
- Page transactions in table view
  - Next page should append to list, search should replace paging many times.
  - Response could include path with query params to get next page or none if at last page.
  - Paging is expected to used infrequently
- Consider how to manage styling across pages/source code files for consistent styling.

## CSV Parsing

We can use representative example CSVs for each format (schema) to generate type providers for type safe access and parsing:

```fsharp
open FSharp.Data

// One type per known format, each generated from a representative sample
type FormatA = CsvProvider<"samples/formatA.csv">
type FormatB = CsvProvider<"samples/formatB.csv">
type FormatC = CsvProvider<"samples/formatC.csv">

// A DU the user (or your detection logic) selects at runtime
type CsvFormat =
    | FormatA
    | FormatB
    | FormatC

// A common domain type all formats get normalized into
type Record =
    { Id: string
      Name: string
      Amount: decimal
      Date: System.DateTime }

let parse (format: CsvFormat) (path: string) : Record seq =
    match format with
    | CsvFormat.FormatA ->
        FormatA.Load(path).Rows
        |> Seq.map (fun r -> { Id = r.Id; Name = r.Name; Amount = r.Amount; Date = r.Date })
    | CsvFormat.FormatB ->
        FormatB.Load(path).Rows
        |> Seq.map (fun r -> { Id = r.RecordId; Name = r.FullName; Amount = r.Total; Date = r.TxDate })
    | CsvFormat.FormatC ->
        FormatC.Load(path).Rows
        |> Seq.map (fun r -> { Id = r.Code; Name = r.Description; Amount = r.Value; Date = r.Timestamp })
```

We also need a function to detect the format/schema of a given CSV file such as:

```fsharp
let detectFormat (path: string) : CsvFormat =
    let header = (System.IO.File.ReadLines path |> Seq.head).Split(',')
    if Array.contains "RecordId" header then CsvFormat.FormatB
    elif Array.contains "Code" header then CsvFormat.FormatC
    else CsvFormat.FormatA
```
