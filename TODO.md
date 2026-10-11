# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [x] Dashboard MVP
- [x] Auto-tagging
- [ ] CSV Imports
- [ ] Quick-tagging
- [ ] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Regular snapshots with balance sheets, income statement
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

CSV imports and accounts. Design and rationale are in `docs/csv-import.md`.

1. Balance sheet dates (`docs/balance-sheet.md` decision 4): in migration `001`,
   remove `BalanceSheets` and add an as-of date to `BalanceSheetItems`; `just
   db-reset` and `just db-update`. Item create and update take an as-of date,
   later than the server's UTC date plus one day rejected, and write no sheet
   date; the read returns an empty sheet instead of `404`. Client: as-of date in
   the item modal (defaulting to today) and on item lines, the client's today as
   the statement date on the balance sheet and dashboard, and no `404` empty
   state. With no `DATETIME` column left, remove `Data/UtcDateTime.fs`, its lint
   in the `justfile`, and the client's `timestamp_helpers`. Tests.
2. Accounts model: in migration `001`, redesign `Accounts` (number nullable and
   unique per user, name, term), add the balance observations table (keyed by
   account and date), make the import hash unique per user, delete transactions
   with their account, and index `Transactions.AccountId`; `just db-reset` and
   `just db-update`. Add the `Account` type with its number and name rules and
   the observation rules to `Domain/`, and their mappings to `Data/`. Tests,
   including account number canonical forms and the observation rules.
3. `Feature/Account/`: CRUD at `/api/accounts`, with manual balance entry
   recording an observation. Balance sheet read model with account lines
   (current balance, side from sign) and unknown balances; transaction responses
   carry the account name. Tests.
4. Client accounts: account lines, unknown-balance callout, and account modal on
   the balance sheet page; account column and account select on the transactions
   page. Client tests, E2E for an account on the balance sheet.
5. Formats: the format type, the interpreter, detection and its errors, and the
   import hash, with the ASB card and Kiwibank formats. Move the samples from
   `SampleCsv/` to test fixtures. Anonymiser script and `just` target. Tests,
   including pinned hash values, Kiwibank observations, and the declared row
   order.
6. `Feature/Import/`: `POST /api/imports` with its own 1 MB body limit; accounts
   found or created, duplicates skipped, transfers marked, rule tags applied,
   daily balance observations recorded, in one database transaction; counts and
   accounts created in the response. Move the transaction mapping to `Data/`,
   delete the empty `ImportTransaction.fs`, and update the body limit gotcha in
   `AGENTS.md` and the proxy notes in `docs/deployment.md`. Tests.
7. Client import: modal on the transactions page, a file-reading effect, result
   toast, error list, table reload. Client tests, E2E uploading the Kiwibank
   chequing and savings samples.

## Backlog

- Dates after the dashboard MVP.
  - Server-side timezone, needed only once the server works out periods without
    a client request (e.g. the regular snapshots on the roadmap): a configured
    default IANA timezone (e.g. `Pacific/Auckland`), validated at startup with
    the other config sections, `tzdata` in the runtime image so
    `TimeZoneInfo.FindSystemTimeZoneById` resolves it, and `today` derived from
    `Clock` plus that zone.
  - Per-user timezone: start with the browser's zone
    (`Intl.DateTimeFormat().resolvedOptions().timeZone`); add a settings page
    once there are other preferences to store.
- Page transactions in table view
  - Next page should append to list, search should replace paging many times.
  - Response could include path with query params to get next page or none if at
    last page.
  - Paging is expected to used infrequently
- Consider how to manage styling across pages/source code files for consistent
  styling.
  - Consider Catppuccin Latte and Mocha
    - Migrate tag colour swatch
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Authelia: Check why Authelia keeps showing consents screen
- Scalar docs: refresh tokens for Authelia
