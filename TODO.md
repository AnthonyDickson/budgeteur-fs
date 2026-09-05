# TODO

## Roadmap

- [x] Transaction CRUD
- [ ] Category (tag) CRUD
- [ ] Rules CRUD
- [ ] Balances (Assets, Liabilities) CRUD
- [ ] Dashboard MVP
- [ ] Auto-tagging
- [ ] CSV Imports
- [ ] Quick-tagging
- [ ] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Regular snapshots with balance sheets, income statement

## Current Tasks

- Tags and rules page:
  - Connect frontend to tags and rules endpoints
    - CRUD for tags
    - CRUD for rules

    UI flow should be:
    request -> show loading spinner, disable buttons
    ok -> hide modal, show success toast
    error -> show error in form, hide loading spinner, enable buttons
    error, modal was dismissed -> show error via toast
    -> update model
  - Refactor common code/patterns
  - In tag form, disable colour picker while submitting
  - Rename to just "tagging page"
  - Clean up naming split between modal/form
  - Move to Catppuccin Latte colour scheme
    - Migrate tag colour swatch
  - Add E2E tests
  - Consider breaking up `tags_and_rules_page.gleam`
  - Ensures docs are up-to-date and sufficient
  - Set transaction tag via create and update transaction dialogs
  - Display transaction tag in transactions table
  - Update docs
- Cut down AGENTS.md to around 150 lines

## Backlog

- Kiwibank statements have enough info to auto tag internal transfers without dedicated rule
  - If the both the source and target account numbers are in the user's accounts, then you can tag as an internal transfer.
  - This should only apply on import, manual imports must be manually categorised.
  - May want user setting around which category to use for internal transfer, or hardcode and force user to use it.
  - Initial imports will be missed if the accounts are not added beforehand
- Add view for empty transactions table, currently it just shows the header and a blank page
- Page transactions in table view
  - Next page should append to list, search should replace paging many times.
  - Response could include path with query params to get next page or none if at last page.
  - Paging is expected to used infrequently
- Consider how to manage styling across pages/source code files for consistent styling.
  - Consider Catppuccin Latte and Mocha
- Reconsider toasts for error handling in modal forms, the toasts are behind the backdrop layer so they are dimmed and
  not clickable.
- Consider a loading state for the transactions page to avoid flashing when loading localstorage backup and then replacing
  it with the server data.

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
