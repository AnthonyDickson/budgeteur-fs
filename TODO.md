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
- [x] Reports: balance sheets and income statements per period
- [ ] Full dashboard w/ charts (planned in docs/dashboard.md)
- [ ] Transaction search
- [ ] Mobile support and UI cleanup
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

Full dashboard, as designed in [docs/dashboard.md](docs/dashboard.md) (decisions
9 to 17): one dashboard read, the month to date against its baseline, twelve
months of history with totals, and two charts. One commit per task, each passing
`just format`, `just lint`, and the tests it touches, and updating the docs its
decisions touch.

1. Dated income statement entries: each entry from the shared query carries its
   transaction date, so one read can be split into months and baseline days. The
   income statement computation ignores it. No change in behaviour.
2. Dashboard periods in `Feature/Dashboard/`, pure: the month to date, the
   history months (twelve complete months plus the month to date, from the month
   containing the user's first observation or transaction), the baseline months
   (complete months starting on or after the first transaction), and each
   baseline month's same days (clamping, a month's last day mapping to the
   other's last day). Unit tests for month ends, leap years, year boundaries,
   and the cutoffs.
3. Month figures against the baseline, pure: the month's income statement and
   savings rate, the baseline for each total and line (the union of tags), the
   change as an amount and a percentage (none for a zero or negative baseline),
   the savings rate baseline as the rate of the baseline means with its change
   in points, the baseline month count, and the latest transaction date. Unit
   tests.
4. History figures, pure: each month's income, expenses, net income, and net
   worth and working capital as of its closing date; the totals and monthly
   averages over the baseline months; runway (none and zero cases); and the
   oldest as-of date among today's lines. Unit tests.
5. Dashboard read: `GET /api/dashboard?today=` returning the position, the
   month, and the history, with OpenAPI field docs. Endpoint tests, including
   user scoping and a user with no data.
6. Dashboard page on the dashboard read: position with runway and its as-of
   date; the month section with typical and change columns, green for
   improvements, the savings rate change in points, share bars as thin strips
   under each expense line, the freshness caption, and the baseline-building
   state. Removes the preset picker, its preference, the client period module
   and its tests, and the balance sheet and income statement reads. Client tests
   and the dashboard E2E spec updated.
7. History section: the totals and the history as tables, before charts. Client
   tests.
8. Charts: Observable Plot in a custom element defined in client FFI, loaded
   only on the dashboard; the cash flow and net worth charts above their tables,
   with the current month drawn as partial.
9. Remove `GET /api/income-statement`: the slice, its tests, and the client API
   route. The architecture doc's examples if they name it.
10. One E2E spec driving the page through its three sections.
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
