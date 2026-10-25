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
- [x] Release 1.0.0
- [ ] Smart tagging ([brief](docs/smart-tagging.md))

## Current Tasks

- Smart tagging, see [docs/smart-tagging.md](docs/smart-tagging.md):
  - Parity fixture.
    - `ml/`: vectorise and fit scikit-learn on an anonymised fixture from
      `server/tests/Budgeteur.Tests/Import/Fixtures` with the shipped features,
      label weights, and square root class balance, to a tight tolerance, and
      write its features and predicted probabilities as committed fixtures.
  - Server: the model in `Domain/` (decisions 2, 3, 4, 7).
    - Add MathNet.Numerics to `Directory.Packages.props`.
    - Vectoriser: character n-grams (3 to 5, within space-padded words) and word
      tokens of the normalised description, TF-IDF from the training set with
      each block normalised; the amount's sign and log2 bucket, and the account,
      as categories.
    - Class balance: the square root factor, rescaled to the original total
      weight.
    - Weighted multinomial logistic regression with L2 (C = 1), optimised with
      L-BFGS from zero; deterministic; a single class predicted outright.
    - Abstaining: threshold 0.7, at least 25 labels, at least 2 labels in the
      predicted class.
    - Policy: a model proposal is suggested, never applied.
    - Tests: gradient check, separable data, row weights, class balance, a
      single class, determinism, each abstain reason, the policy line, and
      parity with the scikit-learn fixtures within a tolerance.
    - Scaling: time fits on training sets resampled to about 1,000, 5,000, and
      10,000 labels, outside CI, and record the results in decision 5 in place
      of the scikit-learn projection.
  - Server: QuickTag slice (decisions 5, 6, 9).
    - `ReadQueue.fs`: load the caller's training set with the queue, fit once
      per read, and suggest from the model for rows no rule matches. Log the
      fit's duration and its label, class, and feature counts in the request
      log, for decision 5's revisit threshold.
    - `Suggestion.fs`: the suggestion's origin becomes a rule with its pattern,
      or the model; counts and the filter use the target whatever the origin.
    - `SuggestionResponse`: the pattern becomes optional, absent for a model
      suggestion, plus an origin field. Check the OpenAPI document.
    - Tests: rule beats model; model suggests only for residual rows; training
      uses only the caller's labels with decision 4's sources and weights; rule
      and model suggestions counted together; accepting a model suggestion
      records `Accepted`.
  - Client: quick tagging page.
    - `queue.gleam`: decode the origin and the optional pattern.
    - `quick_tagging_page.gleam`: the "Suggested" label without a pattern for a
      model suggestion.
    - Tests: a model suggestion decodes and marks its button; choosing it sends
      the suggestion flag.
  - E2E: tag enough transactions by hand to pass the minimums, add a similar
    untagged one, and quick tagging marks the expected tag as suggested.
  - Docs: the updates listed under the brief's Consequences (transfer rules,
    quick tagging, testing strategy), and the changelog.

## Backlog

- Use hand cursor for buttons consistently across the app
- After 1.0.0 release, transfer any learnings and useful patterns over to the
  template project. May want to analyse the codebase and development to see what
  worked well and what didn't work well.
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
