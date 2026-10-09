# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [ ] Dashboard MVP
- [ ] Auto-tagging
- [ ] CSV Imports
- [ ] Quick-tagging
- [ ] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Regular snapshots with balance sheets, income statement
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Dates for the dashboard MVP. Instants are stored as UTC `DATETIME`; calendar dates stay as `DATE` / `DateOnly`.
  - Keep `Transactions.Date` as `DATE` / `DateOnly`: bank CSVs and manual entry give a calendar date, not an instant.
    Remove the TODO comments on `Transactions.Date` and `Accounts.CurrentAsOf` in migration 001. Nothing has been
    released, so migration 001 is edited in place; run `just db-reset` afterwards.
  - Write `docs/dates.md`, a short statement of the date and timestamp conventions, and link it from `AGENTS.md`
    (Conventions) and `docs/database.md`. Move the "Date and datetime columns" section of `docs/database.md` into it.
    Cover:
    - Calendar dates (`DATE` / `DateOnly` / `calendar.Date`) for values the user or a bank statement gives as a day;
      instants (`DATETIME` UTC / `DateTimeOffset` / `Timestamp`) for events the server records.
    - Storage: `DATE` as `yyyy-MM-dd` text, `DATETIME` as UTC without an offset (`UtcDateTime.toColumn`/`fromColumn`).
    - Wire format: ISO-8601 `yyyy-MM-dd` for dates, RFC 3339 with an offset for instants; parsing is culture-invariant.
    - Date ranges are inclusive `from`/`to` dates worked out by the client from its local `today`; the server does not
      convert between timezones yet.
    - Instants are converted to local time only for display.
  - Dashboard endpoints take an explicit inclusive date range (`?from=YYYY-MM-DD&to=YYYY-MM-DD`) and filter
    `Transactions.Date` on it. The client works out the range from its local date (the `GetLocalDate` effect), so the
    server needs no timezone for the MVP and the endpoints are deterministic to test. Exclude `IsInternalTransfer` rows.
  - Put period arithmetic (last N days, calendar month, week, financial year starting 1 April) in a pure client module
    that takes `today` and returns `from`/`to`, with unit tests for month ends, leap years and year boundaries.
  - Validate the range on the server: both dates ISO, `from <= to`, and a maximum span, returning `400` otherwise.
  - Parse dates with `DateOnly.ParseExact (s, "yyyy-MM-dd", CultureInfo.InvariantCulture)` in `Shared/Coders.fs` and
    reuse it for the query parameters; `DateOnly.Parse` depends on the current culture and accepts non-ISO formats.
  - Add an index on `Transactions(UserId, Date)` in migration 001 for range queries. `DATE` values are stored as
    `yyyy-MM-dd` text, so range comparisons are lexical and only correct while every write uses that format.

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
- Consider a loading state for the transactions page to avoid flashing when loading localstorage backup and then
  replacing it with the server data.
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
