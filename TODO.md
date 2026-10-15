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
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Styling ([design brief](docs/styling.md)), one commit each:
  1. [x] Add the Catppuccin palette layer (Latte only) and the role layer to the
         stylesheet, declare the light colour scheme, and give the page its
         background and text roles. Check the mixed roles' contrast against
         decision 6 (decisions 1, 3, 4, 6).
  2. [x] Move `modal_ui`, `row_ui`, and `tag_ui` into `shared/ui/` as `dialog`,
         `row`, and `swatch`, with no visual change (decision 11).
  3. [x] Add `ui/button` with its variants on roles, and use it for the modal
         buttons and every page button (decision 11).
  4. [ ] Add `ui/input` (text input, select, checkbox, invalid state) and
         replace the copied input classes (decision 11).
  5. [ ] Add `ui/card` (panel, empty state) and `ui/banner` (error, warning) and
         use them; toasts use the status tints (decisions 7 and 11).
  6. [ ] Move the remaining colours to roles in the shell, header, and
         transactions page with its modals (decision 4).
  7. [ ] Move the remaining colours to roles in the tagging page with its modals
         (decision 4).
  8. [ ] Move the remaining colours to roles in the balance sheet and line
         details pages with their modals (decision 4).
  9. [ ] Move the remaining colours to roles in the dashboard, reports, and
         quick tagging pages; the improvement figure becomes a success pill
         (decisions 4 and 7).
  10. [ ] Draw the charts with roles. Check first that Plot accepts CSS variable
          references as colours (decision 10).
  11. [ ] Make tag colours accent names: `TagColor` union with parse, print, and
          enum hint, and tests; client colour type, 14-colour picker, and swatch
          from the palette variable; E2E test ids by name; reset the development
          database (decision 9).
  12. [ ] Clear Tailwind's default palette and replace the remaining white and
          black (decision 8).
  13. [ ] Add Mocha for the dark colour scheme, with an E2E test for each
          scheme; check every page in both modes by hand (decisions 2 and 6).
  14. [ ] Docs: AGENTS.md role rule, a styling section in the architecture doc's
          client section, dashboard decision 15, and remove the styling backlog
          item.

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
