# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [x] Dashboard MVP
- [x] Auto-tagging
- [x] CSV Imports
- [x] Quick-tagging
- [ ] Reports: balance sheets and income statements per period (planned in
      docs/reports.md)
- [ ] Full dashboard w/ charts (planned in docs/dashboard.md, after reports)
- [ ] Transaction search
- [ ] Mobile support and UI cleanup
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

Reports, as designed in [docs/reports.md](docs/reports.md): item observations,
closing lines, observation history, and a reports page. One commit per task,
each passing `just format`, `just lint`, and the tests it touches, and updating
the docs its decisions touch.

1. Renames: an item's `Balance` becomes `Value`, and `ItemKind` becomes `Side`
   for items and account lines. Covers migration `001` (`just db-reset`, `just
   db-update`), domain, codecs, API, client, tests, and the balance sheet brief.
   No change in behaviour.
2. Item observations: in migration `001`, add the item observations table and
   drop the item's value and as-of date. An `ItemObservationStore` records them,
   replacing any on the same date. Item create writes the first observation with
   the item; item update no longer takes a value; `POST
   /api/balance-sheet/items/{id}/observations` records one. The balance sheet
   read uses each item's latest observation. Client: the item form keeps its
   value fields on create only, and item rows get a record action using the
   balance form. Tests and E2E specs.
3. Closing lines: in migration `001`, add a close date to items and accounts,
   set and cleared in their edit forms. `GET /api/balance-sheet` leaves closed
   lines out of the sheet and returns them apart; the page lists them in a
   collapsed section. Tests, the CSV import brief's closed account wording, and
   E2E specs.
4. Observation history API: list (newest first) and delete for items (`GET` and
   `DELETE /api/balance-sheet/items/{id}/observations[/{asOf}]`) and accounts
   (the same under `/api/accounts/{id}/observations`, with account recording
   moving from `/balances` to `/observations`). Deleting an item's last
   observation returns `400`. Endpoint tests, including user scoping.
5. Observation history page: client routes with an id
   (`/balance-sheet/items/{id}`, `/balance-sheet/accounts/{id}`), the page
   module in the balance sheet feature, links from line names, the record
   action, and deletes confirmed with the delete dialog. Client tests for load,
   delete, and a failed delete; one E2E spec.
6. Move the income statement computation to `Domain/`. No change in behaviour.
7. Balance sheet for a statement date in `Domain/`: a pure function over the
   user's items, accounts, and observations (latest observation on or before the
   date, lines entering at their first observation, closed lines, unknown
   accounts). Unit tests.
8. Reporting periods in `Domain/`: the four frequencies, aligning a date to its
   period, completeness against `today`, and financial year labels. Unit tests
   for quarters, year and financial year boundaries, and leap years.
9. Report read: `Feature/Report/` with `GET
   /api/reports?frequency=&date=&today=`, returning the period, completeness,
   opening and closing net worth and working capital, change in net worth, net
   income, other changes (not meaningful for an empty opening sheet), savings
   rate, the income statement, the closing balance sheet, and whether earlier
   and later reports exist. Compute and endpoint tests.
10. Reports page: route and header link, frequency picker saved to localStorage,
    previous and next controls, opening on the latest complete period. Client
    tests and one E2E spec.
11. Tick the roadmap item and clear these tasks.

## Backlog

- Cent level precision is probably only needed for transaction table and data
  entry
- Dates after the dashboard MVP.
  - Server-side timezone, needed only once the server works out periods without
    a client request (e.g. a scheduled job): a configured default IANA timezone
    (e.g. `Pacific/Auckland`), validated at startup with the other config
    sections, `tzdata` in the runtime image so
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
