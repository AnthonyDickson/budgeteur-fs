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
- [x] Full dashboard w/ charts
- [ ] Transaction search
- [ ] Mobile support and UI cleanup
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Transaction search ([design brief](docs/transaction-search.md)), one commit
  each:
  1. [x] Add the description-matching SQL function in `Data/`, with tests for
         ASCII and non-ASCII case and literal `%` and `_` (decision 2). Check
         first that SqlHydra renders a marked function in a `where` clause.
  2. [ ] Add the pure search module in the Transaction slice: request types,
         criteria validation, preset resolution through the reporting periods,
         and the cursor (decisions 3-6).
  3. [ ] Add `POST /api/transactions/search` returning a page and the next
         cursor, with endpoint tests for each criterion, user scoping, and
         paging (decisions 6 and 7).
  4. [ ] Client: fetch the page through search with no criteria and add "Load
         more", skipping rows already shown; patch updates in place, add creates
         at the top, and run the search again after an import; remove
         client-side sorting (decisions 6 and 10).
  5. [ ] Client: add the search box with debounced searches, ignored stale
         responses, "Searching…", the no-match empty state, and "Clear"
         (decisions 9 and 11).
  6. [ ] Client: add the filters panel and the dates select with presets, custom
         dates, and the resolved range (decisions 3 and 11).
  7. [ ] Client: add the account and tag selects to the filters panel (decision
         4).
  8. [ ] Client: add the direction, minimum, and maximum fields with field
         validation (decisions 5 and 9).
  9. [ ] E2E: search by text, narrow by tag, edit a match so it no longer
         matches and check it stays listed, clear.
  10. [ ] Register `GET /api/transactions` in development only (decision 7).

## Backlog

- Consider how to manage styling across pages/source code files for consistent
  styling.
  - Consider Catppuccin Latte and Mocha
    - Migrate tag colour swatch
- Except for transaction table and data entry, consider rounding to the nearest
  dollar
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Authelia: Check why Authelia keeps showing consents screen
- Scalar docs: refresh tokens for Authelia
