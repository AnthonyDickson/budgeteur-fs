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
- [ ] Mobile support and UI cleanup
- [ ] Release
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Highlight pills for improved values in dashboard make the numbers misaligned.
- Pages are quite flat, esp. dashboard
- Lots of little notes that clutter the screen may be better as popovers (use native popover API)
- Pages are different widths, e.g. transactions vs dashboard
- Quick-tagging page:
  - It is difficult tell whether a transactions has been tagged or not.
  - No obvious feedback that the transaction was tagged
- Transactions page:
  - Add tag colour dot to make tags stick out more and easier to scan?
  - Difficult to distinguish credits from debits without colour.
- Reports page:
  - No clear visual differentiation between line items and totals.

## Backlog

- Except for transaction table and data entry, consider rounding to the nearest
  dollar
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Authelia: Check why Authelia keeps showing consents screen
- Scalar docs: refresh tokens for Authelia
