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
- [x] Transaction search
- [x] Mobile support
- [ ] Release 1.0.0
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

None

## Backlog

- Except for transaction table and data entry, consider rounding to the nearest
  dollar
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Scalar docs: refresh tokens for Authelia
- Edit a balance history entry: an Edit button per entry that opens the record
  modal pre-filled with its amount and date. Reverses decision 9 in
  docs/reports.md ("there is no edit action"). Changing the date would add an
  entry rather than move it, so keep the date read-only when editing, or delete
  and record in one transaction on the server.
- Display dates in a friendlier format, e.g. "18 Oct 2026": a `date.display`
  through `Intl.DateTimeFormat("en-NZ")` for the text call sites, keeping ISO
  `date.format` for the API, date inputs, and test ids. Server messages and E2E
  assertions on visible dates would change too.
