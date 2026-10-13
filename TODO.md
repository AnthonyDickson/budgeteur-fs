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

Quick tagging. Design and rationale are in `docs/quick-tagging.md`. One commit
per task, each passing `just format`, `just lint`, and the tests it touches.
Writes come before the queue read so the read's tests can dismiss through the
API.

1. Dismissed assignment state (decision 1): in migration `001`, make
   `TagAssignments.TagId` nullable with the `Manual` source check; `just
   db-reset` and `just db-update`. The assignment type in `Domain/` gains the
   dismissed case; the codec maps it. Transitions: the transaction form keeps a
   dismissal when saved without a tag and replaces it when given one; marking a
   transfer removes any assignment, dismissals included; tag untagged and re-tag
   never change a dismissal. Transaction responses give a dismissal no tag. Unit
   tests for the transitions; update auto-tagging decision 4.
2. Quick tag writes (decision 6): `Feature/QuickTag/` with `PUT
   /api/quick-tag/{transactionId}` and `DELETE /api/quick-tag/{transactionId}`,
   the quick tag transitions in `Domain/`, and the slice's endpoint
   registration. Tests: tag, dismiss, both idempotent, `404` for another user's
   transaction, `400` for a tag the user does not have and for a transfer, and
   tag untagged leaving a dismissed transaction alone.
3. Queue read (decision 2): `GET /api/quick-tag` returning the batch, newest
   first, and the total. Tests: only the caller's untagged non-transfer
   transactions, tagged and dismissed excluded, order, batch size, total.
   Resolve the deferred tagging queue in auto-tagging.
4. Quick tagging page, read only (decisions 7 and 8): route `/quick-tagging`,
   page module, queue and tag loads, rows, waiting count, empty state, error
   with retry, "Next batch", and the "Quick tag" link in the transactions page
   header. Client tests for load, retry, and next batch. Update CSV import
   decision 11 and its deferred quick-tagging entry.
5. One-click tagging (decisions 3 to 5): native tag and "Dismiss" buttons in a
   fixed order, rows kept in place with the chosen button pressed, a row's
   buttons disabled while its request is in flight, the previous state and the
   error toast on failure, and the waiting count. Client tests for each. E2E:
   from the transactions page, tag a transaction, reload, and see the queue
   empty and the tag in the transactions table.
6. Dashboard queue total (decision 7): remove the untagged count from the income
   statement (computation, response, tests, client decoder); the dashboard
   fetches the queue total with its own decoder and the untagged note links to
   quick tagging. Update the dashboard E2E spec and `docs/dashboard.md` (the
   response shape, the untagged note, and the deferred quick tagging entry).
7. Mark quick tagging done in the roadmap and clear these tasks.

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
