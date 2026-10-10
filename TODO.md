# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [x] Dashboard MVP
- [ ] Auto-tagging
- [ ] CSV Imports
- [ ] Quick-tagging
- [ ] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Regular snapshots with balance sheets, income statement
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Clean up AGENTS.md and docs
  - Move details out of AGENTS.md into docs/
  - Document key design requirements and decisions in docs/. These should be a high-level spec to record design intent
    and requirements.
  - Ensure documentation for implementation details stays in the code.

## Backlog

- Dates after the dashboard MVP.
  - Server-side timezone, needed only once the server works out periods without a client request (e.g. the regular
    snapshots on the roadmap): a configured default IANA timezone (e.g. `Pacific/Auckland`), validated at startup with
    the other config sections, `tzdata` in the runtime image so `TimeZoneInfo.FindSystemTimeZoneById` resolves it, and
    `today` derived from `Clock` plus that zone.
  - Per-user timezone: start with the browser's zone (`Intl.DateTimeFormat().resolvedOptions().timeZone`); add a
    settings page once there are other preferences to store.
  - The balance sheet subtitle converts `StatementDate` with today's offset (`calendar.local_offset()`), so an instant
    from the other side of a DST change can show the wrong date within an hour of midnight. Convert with the offset at
    that instant (e.g. via a JS `Date` FFI) or the user's IANA timezone.
  - `Accounts.CurrentAsOf` needs no work: `Accounts` is only used as the target of `Transactions.AccountId` and may be
    replaced by the balance sheet. Revisit when CSV imports decide what an account is.
- Kiwibank statements have enough info to auto tag internal transfers without dedicated rule
  - If the both the source and target account numbers are in the user's accounts, then you can tag as an internal
    transfer.
  - This should only apply on import, manual imports must be manually categorised.
  - May want user setting around which category to use for internal transfer, or hardcode and force user to use it.
  - Initial imports will be missed if the accounts are not added beforehand
- Page transactions in table view
  - Next page should append to list, search should replace paging many times.
  - Response could include path with query params to get next page or none if at last page.
  - Paging is expected to used infrequently
- Consider how to manage styling across pages/source code files for consistent styling.
  - Consider Catppuccin Latte and Mocha
    - Migrate tag colour swatch
- For modals, ensure that focus is returned to the element focused before opening the modal. This is needed due to the
  custom dialog wrapped deleting the wrapping DOM element instead of calling `.close()` on the native dialog.
- Authelia: Check why Authelia keeps showing consents screen
- Scalar docs: refresh tokens for Authelia

## CSV Parsing

We can use representative example CSVs for each format (schema) to generate type providers for type safe access and
parsing:

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
