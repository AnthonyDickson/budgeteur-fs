# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [x] Dashboard MVP
- [x] Auto-tagging
- [x] CSV Imports
- [ ] Quick-tagging
- [ ] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Regular snapshots with balance sheets, income statement
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

CSV import feedback, one commit per group. After each server commit run `just
server-build` and `just server-test`; after each client commit run `just
client-test`. Finish with `just e2e-test`, `just lint`, and `just format`.

- [x] **Client fixes**
  - [x] Import toast stays until dismissed: the import success toast in
        `transaction_page.gleam` uses no auto-dismiss. Update decision 13 in
        `docs/csv-import.md`.
  - [x] New rule defaults to the selected tag (bug from before this branch):
        `rule_modal.gleam` sets `value` on the `<select>`, which the browser
        applies before the options exist, so it shows the first tag. Mark the
        matching option `selected`, as `transaction_modal.gleam` does. E2E:
        select the second tag, open "New rule", assert the select shows it.
- [x] **Current balances as a view**
  - [x] Add a `CurrentBalances` view to migration 001 (unreleased): each
        observation whose as-of date is the latest for its account. Comment it
        as the "latest observation is current" rule. Run `just db-update`.
  - [x] Verify SqlHydra generates the view. SQLite reports view columns as
        nullable, so its fields may be options. Fallback: a correlated subquery
        (`correlate`, `subqueryOne`) in one shared reader in `Data/`.
  - [x] Move `AccountBalance` from `Domain/BalanceSheet.fs` to
        `Domain/Account.fs`; delete `BalanceObservation.current`.
  - [x] `AccountQuery.readAll`/`tryRead` and the balance sheet reader become one
        query each: accounts left joined to `CurrentBalances`. Removes
        `AccountQuery.withCurrent` and `ReadBalanceSheet.accountBalances`.
  - [x] Tests: drop the `BalanceObservation.current` unit tests; add an endpoint
        test that a balance recorded for an older date after a newer one does
        not become current (account and balance sheet reads).
  - [x] Docs: decisions 3 and 12 in `docs/csv-import.md`: the current balance is
        a view because it is a read model, not a write-side decision.
- [x] **Read back inside the write transaction**
  - [x] `AccountQuery` takes a `QueryContext`; `ReadAccount` and
        `ReadAllAccounts` open their own.
  - [x] `CreateAccount` and `UpdateAccount`: write, read back with the same
        context, then commit. The `None` branch stays for the option type but
        cannot follow a successful write.
  - [x] Same change in the Transaction slice (`CreateTransaction`,
        `UpdateTransaction`, `TransactionQuery`) so the reference implementation
        matches.
  - [x] Docs: if `docs/architecture.md` describes write responses, note the read
        happens in the write transaction.
- [ ] **Separate balance and details operations: server**
  - [ ] Rename `WriteAccountRequest.fs` to `BalanceEntryRequest.fs`, keeping the
        balance entry and its validation.
  - [ ] `CreateAccount.fs` defines `CreateAccountRequest` with an optional
        opening balance.
  - [ ] `UpdateAccount.fs` defines `UpdateAccountRequest` (name, number, term)
        and writes only the account row.
  - [ ] New `RecordBalance.fs`: `POST /api/accounts/{id}/balances` takes a
        balance entry, checks the account is the user's (404 otherwise), upserts
        through `BalanceObservationStore`, reads back in the same transaction,
        and returns the account. Responses 200, 400, 401, 404.
  - [ ] Tests: split requests; record, replace on the same date, another user's
        account, future date; `PUT` leaves balance history unchanged.
  - [ ] Docs: decision 12 in `docs/csv-import.md`.
- [ ] **Separate balance and details operations: client**
  - [ ] Extract `balance_form.gleam` from `account_modal`: side, amount, as-of
        date, validation, signed balance, view. Radios "Asset" and "Liability",
        legend "Balance", help text: "Liability when the account is overdrawn or
        a card balance is owing. The line moves sides when the balance changes
        sign."
  - [ ] New `balance_modal.gleam` titled "Record balance", on `form_modal` in
        edit mode, mapping its `Put` to a record-balance request. Prefills side
        and amount from the current balance and the date with today; shows the
        current balance and its date; help text that keeping the current
        balance's date corrects it. Blank amount for an unknown balance.
  - [ ] `account_modal`: create has details plus an optional balance form; edit
        has details only. Update its module doc.
  - [ ] Split `account_write_request.gleam` into create, update, and balance
        entry payloads.
  - [ ] Line actions move under the details (`line_row` takes a list of actions;
        row `items-start`; `text-xs` buttons), so amounts line up with section
        totals. Accounts: "Record balance · Edit · Delete"; items: "Edit ·
        Delete". Add `data-testid`s.
  - [ ] Unknown-balance callout: heading "Unknown balances"; its button opens
        the balance modal.
  - [ ] Client tests: update `account_modal_test.gleam`; add
        `balance_modal_test.gleam` (prefill, side flips sign, date required,
        negative rejected, unknown balance starts blank).
  - [ ] E2E: recording a liability balance on an asset account moves the line
        and updates totals; editing details leaves the balance; update
        selectors.
  - [ ] Docs: decision 13 in `docs/csv-import.md`; `docs/balance-sheet.md` if it
        describes line actions.
- [ ] **Docstrings and language**
  - [ ] `BalanceAfter` in `Statement.fs`: "The balance a row's running-balance
        column reports: the account's balance once the row is applied, and the
        date it is accurate as of, which may differ from the transaction date."
  - [ ] One set of direction words: Asset/Liability (owned/owed). Update the
        Balance entry in the `docs/csv-import.md` glossary and the "positive is
        held, negative is owed" comments (`Domain/Account.fs`,
        `WriteAccountRequest.fs`, `AccountResponse.fs`,
        `account_write_request.gleam`, migration 001).
  - [ ] Qualify Balance in both glossaries: item balance (magnitude) vs account
        balance (signed).
  - [ ] Disambiguate Statement in both glossaries: Import uses the bank's sense
        (one CSV file, which the bank calls an export); statement date is the
        financial-statement sense.

Not changing: `unknownBalances` decoded as `Dynamic` on the dashboard. It only
checks whether the lists are empty; concrete types would mean importing the
balance sheet page's decoders or duplicating them.

## Backlog

- Cent level precision is probably only needed for transaction table and data
  entry
- Language renames deferred from the CSV import feedback:
  - An item's `Balance` (a magnitude) and an account's balance (signed) share a
    word. Consider renaming the item's to `Value`; touches the item type, codec,
    API, and client.
  - Account lines use `ItemKind` for their side, though an account is not an
    item. Consider a `Side` type; touches the API.
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
