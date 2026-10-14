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

- Move Reports after dashboard in navbar
- Except for transaction table and data entry, round to the nearest dollar
- Page transactions in table view
  - Next page should append to list, search should replace paging many times.
  - Response could include path with query params to get next page or none if at
    last page.
  - Paging is expected to used infrequently
- Plan out transaction search

## Backlog

- Consider how to manage styling across pages/source code files for consistent
  styling.
  - Consider Catppuccin Latte and Mocha
    - Migrate tag colour swatch
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Authelia: Check why Authelia keeps showing consents screen
- Scalar docs: refresh tokens for Authelia
