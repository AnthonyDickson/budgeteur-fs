# Dashboard

Design brief for the dashboard MVP. It records what we decided, why, and what each decision is meant to achieve, so the
tag, income statement, and page work has one written source of intent. Change it when the reasoning changes.

The previous Rust project (`budgeteur`, `server/src/dashboard/`) built two dashboards: an HTML page with charts, summary
tables, and expenses-by-tag cards, and a JSON/TUI view with net worth history, net income, spending pace, and savings
runway. Lessons from it are cited where they shaped a decision.

## Goal

Give the user one page that answers two questions:

- **Where do I stand?** Net worth and working capital, from the balance sheet.
- **Where did my money go this period?** Income, expenses, and net income for a date range, with expenses broken down by
  tag.

The MVP shows figures and tables only. Charts, comparisons against a baseline, and history are later work (see
[Deferred](#deferred)).

## Ubiquitous language

| Term             | Meaning                                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| Period           | An inclusive `from`/`to` pair of calendar dates. See [dates.md](dates.md).                                  |
| Preset           | A named rule that turns the client's `today` into a period, e.g. "This month".                              |
| `TagKind`        | `Income` or `Expense`. Set by the user on each tag. Decides which side of the income statement a tag is on. |
| Income statement | Income, expenses, and net income for a period, broken down into lines.                                      |
| Line             | One tag's net amount for the period, or the untagged income or untagged expenses.                           |
| Net income       | Income minus expenses.                                                                                      |
| Net worth        | As in [balance-sheet.md](balance-sheet.md).                                                                 |
| Working capital  | As in [balance-sheet.md](balance-sheet.md).                                                                 |

## Decisions

### 1. The dashboard pairs the balance sheet with an income statement

- **Decision**: the page shows two statements. The balance sheet (a stock, as of `StatementDate`) comes from the
  existing `GET /api/balance-sheet`. The income statement (a flow, over a period) is a new slice,
  `Feature/IncomeStatement/`.
- **Why**: these are the two standard personal finance statements, and the roadmap already names both ("balance sheets,
  income statement"). Naming the flow side now means the later periodic snapshots extend it rather than rename it.
- **Goal**: the dashboard is a composition of domain statements, not a bespoke aggregate that only the dashboard
  understands.

### 2. Tags carry a kind: `Income` or `Expense`

- **Decision**: add `TagKind` to `Tag`, required on create and editable on update. `IsTransfer` stays a per-transaction
  flag rather than a third kind.
- **Why**: budgeting tools (YNAB, Actual, Monarch, Tiller) and double-entry accounting all give each category a fixed
  type and never infer it from the sign of an amount. Inferring it means a tag can switch sides between periods, e.g. an
  electronics tag becomes income in the month a laptop is returned.
- **Goal**: the income statement classifies by a fact the user stated, so a tag is on the same side in every period.
- **Changing the kind**: allowed. It reclassifies past periods in every report; the stored transactions do not change.
  This matches the tools above.
- **Schema**: `Tags.Kind TEXT NOT NULL CHECK (Kind IN ('Income', 'Expense'))`. Migration `001` has not been released (no
  version tag contains it), so the column is added in place.
- **Delivery**: its own commit, before the income statement.

### 3. Lines net per tag; the kind decides the side

- **Decision**: sum each tag's transactions in the period. `Income` tags are income lines and `Expense` tags are expense
  lines, whatever the sign of the sum. An expense line is shown as a positive amount spent, so an expense tag with more
  refunds than spending is a negative expense, and an income tag with a clawback reduces income. Untagged transactions
  have no kind, so they are split by sign into "Untagged income" and "Untagged expenses".
- **Why**: a refund is money returning to the category it left (a contra-expense in accounting terms), not income.
  Classifying each transaction by sign would count refunds as income and overstate both sides. Untagged transactions are
  split rather than netted because the bucket mixes salary with spending, and netting would let one hide the other.
- **Goal**: each expense line answers "how much did this category cost me", and the lines on each side sum to that
  side's total.
- **Totals**: income is the sum of income lines, expenses is the sum of expense lines, net income is income minus
  expenses.
- **Share**: each expense line carries its share of total expenses, as a percentage rounded to two decimal places. A
  negative expense line has a negative share; the share is omitted when total expenses are zero or negative.

### 4. The client supplies the period

- **Decision**: the endpoint takes `?from=YYYY-MM-DD&to=YYYY-MM-DD`. The client works out the period from its local
  `today` (the `GetLocalDate` effect).
- **Why**: covered in [dates.md](dates.md). The previous project derived `today` on the server and needed a configured
  timezone to do it.
- **Validation**: both dates parse with `Coders.Extra.DateOnly.tryParse`, `from <= to`, and the span is at most 366
  days. Failures are combined with FsToolkit's `validation` into one `400`. (`requireAll` is for checks that mirror
  database constraints.)
- **Goal**: no server timezone for the MVP, and endpoint tests are deterministic.

### 5. Aggregation runs in F# on `decimal`

- **Decision**: load the user's non-transfer transactions in the period (joined to their tags) and aggregate with a pure
  function, `IncomeStatement.compute`. Do not use SQL `SUM`.
- **Why**: SQLite sums in floating point, and the money rule is that all aggregation uses the backend `decimal`. A year
  of personal transactions is small enough to load.
- **Goal**: one tested function owns the income statement rules; the handler only queries and maps.
- **Ownership**: the function lives in the slice. It moves to `Domain/` when a second slice (e.g. snapshots) needs it.

### 6. Month to date is the default period

- **Decision**: the default preset is "This month" (the first of the month up to `today`). The other presets are "Last
  month", "Last 28 days" (`today - 27` to `today`), and "This financial year" (from 1 April). The chosen preset is saved
  to localStorage, the one kind of data the client keeps there (preferences, never server data).
- **Why**: monthly periods are the default in budgeting tools and match bills, statements, and monthly budgets. An
  income statement covers a fixed reporting period, not a rolling one. A month-to-date figure only changes when
  transactions are added, while a rolling window changes as old days leave it, and monthly items (rent, a monthly
  salary) leave a 28-day window for a few days each month.
- **Known weakness**: early in the month the figures are small and say little on their own. The fix is a baseline
  comparison (deferred, below), not a different default window.
- **Period arithmetic**: a pure client module that takes `today` and a preset and returns `from`/`to`, with unit tests
  for month ends, leap years, and year boundaries. The previous project had two versions of "last twelve months", one of
  which gets the range wrong in January.
- **Goal**: every figure on the page covers the same, explicitly labelled period. The previous project mixed 28-day,
  calendar month, and trailing twelve-month figures on one page.

### 7. Separate endpoints, no dashboard aggregate

- **Decision**: the page calls `GET /api/balance-sheet` and `GET /api/income-statement`. There is no `/api/dashboard`.
- **Why**: slices do not import each other, and a dashboard endpoint would need both. Changing the period only
  re-requests the income statement.
- **Goal**: each slice stays independent, and the page composes them.

### 8. No charts in the MVP

- **Decision**: the MVP shows figures and tables only.
- **Why**: "Full dashboard w/ charts" is a separate roadmap item. The previous project's dashboard grew to about 4,000
  lines of charts, cards, and statistics before the underlying figures were settled.
- **Goal**: settle the income statement rules first, then build charts on them.

## Consequences

- **Tag API.** Tag create, update, and read requests and responses carry `Kind`. The tag modal gets a kind select;
  tag-creating test helpers and E2E specs supply one.
- **Response shape** (`ReadIncomeStatement.fs` holds the field docs):

  ```text
  IncomeStatement {
    From; To;
    Income; Expenses; NetIncome;
    IncomeLines:  [ Line ];
    ExpenseLines: [ Line & { Share: decimal option } ];
    UntaggedCount
  }
  Line { TagId: Guid option; Name; Color: option; Amount }
  ```

  Untagged lines have no `TagId` or colour. Lines are sorted by amount, largest first, with the untagged line last.
- **Empty states.** A period with no transactions shows a link to the transactions page. A missing balance sheet (`404`)
  is an empty state with a link to the balance sheet page, as on that page. A non-zero `UntaggedCount` shows a link to
  the transactions page.
- **Route.** The dashboard is the `/` route, which currently renders the 404 page.
- **Client read shapes.** The dashboard page decodes only the balance sheet fields it shows, with its own decoder,
  rather than importing the balance sheet page's.
- **Tests.**
  - Server: unit tests for `IncomeStatement.compute` (refunds, negative expense lines, clawbacks, untagged split, empty
    period, shares, rounding); endpoint tests for the happy path, validation, transfer exclusion, and user scoping.
  - Client: unit tests for the period module; `update` tests for load, period change, and error/retry.
  - E2E: create tagged transactions, open `/`, and assert the totals.

## Implementation order

1. Tag kind (own commit): schema, `Domain/Tag.fs`, tag codec and endpoints, client tag type and modal, tests.
2. Income statement slice: `compute`, `ReadIncomeStatement.fs`, OpenAPI metadata, tests.
3. Client period module and tests.
4. Dashboard page, `/` route, header link, `update` tests, E2E test.

## Deferred

- **Baseline comparison and spending pace.** Part of the charts work. A period figure needs a baseline to be read, as a
  snapshot (this figure vs the baseline) and as a trend (cumulative spending through the period vs the baseline by day).
  Baselines to support:
  - the previous period of the same length: month to date vs the same days last month, last 28 days vs the 28 days
    before;
  - the average for the period over trailing periods, e.g. the mean of the last 12 complete months.

  The previous project's expenses-by-tag spec compared the last complete month against the average of earlier months for
  the same reason: a partial period on its own is misleading.
- **Charts and monthly tables.** Need month-bucketed series of the income statement.
- **Net worth and savings history.** Needs balance sheet snapshots. The previous project rebuilt history by subtracting
  transactions from current account balances, which is only correct if every account's transactions are imported.
- **Savings runway.** Builds on a baseline of average monthly expenses.
- **Excluded tags.** `IsTransfer` covers the main use (internal transfers). Revisit if another use appears.
- **Untagged transaction list with quick tagging.** The "Quick-tagging" roadmap item.
- **Data freshness.** Bank exports lag a few days, so the newest days of any period are incomplete. If that becomes
  noticeable, show the latest transaction date.

## Assumptions

- Single base currency, as in [balance-sheet.md](balance-sheet.md).
- Every tag is either income or expense. Transfers are excluded by `IsTransfer`, not by tag.
