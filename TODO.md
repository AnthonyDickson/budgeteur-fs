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

## Backlog

- After 1.0.0 release, transfer any learnings and useful patterns over to the
  template project. May want to analyse the codebase and development to see
  what worked well and what didn't work well.
- On report page: it would be nice to have the net income value next to the
  change in net worth and other changes. Consider a different format that better
  shows the relationship between all the numbers and how they're derived.
- Have auto-tagging rules be able to target transfers as well as tags?
- On iOS, scrolling down and then opening a modal causes the modal to only cover
  the top 3/4 of the page, leaving the bottom 1/4 interactable and without the
  background dimming. Opening a modal without scrolling, or on desktop with or
  without scrolling works as expected. Intermittent, cannot reproduce as of
  writing
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
