# Dashboard

Design brief for the dashboard. It records what we decided, why, and what each
decision is meant to achieve, so later changes have one written source of
intent. Change it when the reasoning changes.

The brief has two parts. The [MVP](#mvp-decisions) is built. The
[full dashboard](#full-dashboard) is planned and waits on the snapshots roadmap
item; where it replaces an MVP decision, both decisions say so.

The previous Rust project (`budgeteur`, `server/src/dashboard/`) built two
dashboards: an HTML page with charts, summary tables, and expenses-by-tag cards,
and a JSON/TUI view with net worth history, net income, spending pace, and
savings runway. Lessons from it are cited where they shaped a decision.

## Goal

Give the user one page that answers two questions:

- **Where do I stand?** Net worth and working capital, from the balance sheet.
- **Where did my money go this period?** Income, expenses, and net income for a
  date range, with expenses broken down by tag.

The MVP shows figures and tables only. The full dashboard adds comparisons
against a baseline, two ratios, and twelve months of history with charts.

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
| Baseline         | The mean of a figure over earlier periods of the same shape. What "typical" means on the page.              |
| Complete month   | A calendar month whose last day is on or before the client's `today`.                                       |
| Savings rate     | Net income as a percentage of income.                                                                       |
| Runway           | Working capital divided by average monthly expenses: how many months it would cover.                        |
| History          | The last twelve complete months plus the current month to date.                                             |

## MVP decisions

### 1. The dashboard pairs the balance sheet with an income statement

- **Decision**: the page shows two statements. The balance sheet (a stock, as of
  today) comes from the existing `GET /api/balance-sheet`. The income statement
  (a flow, over a period) is a new slice, `Feature/IncomeStatement/`.
- **Why**: these are the two standard personal finance statements, and the
  roadmap already names both ("balance sheets, income statement"). Naming the
  flow side now means the later periodic snapshots extend it rather than rename
  it.
- **Goal**: the dashboard is a composition of domain statements, not a bespoke
  aggregate that only the dashboard understands.

### 2. Tags carry a kind: `Income` or `Expense`

- **Decision**: add `TagKind` to `Tag`, required on create and editable on
  update. A transfer is a categorisation of its own rather than a third kind
  ([quick tagging](quick-tagging.md) decision 1).
- **Why**: budgeting tools (YNAB, Actual, Monarch, Tiller) and double-entry
  accounting all give each category a fixed type and never infer it from the
  sign of an amount. Inferring it means a tag can switch sides between periods,
  e.g. an electronics tag becomes income in the month a laptop is returned.
- **Goal**: the income statement classifies by a fact the user stated, so a tag
  is on the same side in every period.
- **Changing the kind**: allowed. It reclassifies past periods in every report;
  the stored transactions do not change. This matches the tools above.

### 3. Lines net per tag; the kind decides the side

- **Decision**: sum each tag's transactions in the period. `Income` tags are
  income lines and `Expense` tags are expense lines, whatever the sign of the
  sum. An expense line is shown as a positive amount spent, so an expense tag
  with more refunds than spending is a negative expense, and an income tag with
  a clawback reduces income. Untagged transactions have no kind, so they are
  split by sign into "Untagged income" and "Untagged expenses".
- **Why**: a refund is money returning to the category it left (a contra-expense
  in accounting terms), not income. Classifying each transaction by sign would
  count refunds as income and overstate both sides. Untagged transactions are
  split rather than netted because the bucket mixes salary with spending, and
  netting would let one hide the other.
- **Goal**: each expense line answers "how much did this category cost me", and
  the lines on each side sum to that side's total.
- **Totals**: income is the sum of income lines, expenses is the sum of expense
  lines, net income is income minus expenses.
- **Share**: each expense line carries its share of total expenses, as a
  percentage rounded to two decimal places. A negative expense line has a
  negative share; the share is omitted when total expenses are zero or negative.

### 4. The client supplies the period

- **Decision**: the endpoint takes `?from=YYYY-MM-DD&to=YYYY-MM-DD`. The client
  works out the period from its local `today` (the `GetLocalDate` effect).
- **Why**: covered in [dates.md](dates.md). The previous project derived `today`
  on the server and needed a configured timezone to do it.
- **Validation**: both dates must be `yyyy-MM-dd`, `from <= to`, and the span is
  at most 366 days. Every failure is reported in one `400`.
- **Goal**: no server timezone for the MVP, and endpoint tests are
  deterministic.
- **Full dashboard**: the dashboard endpoints take the preset and `today`
  instead (decision 11). `GET /api/income-statement` keeps this interface.

### 5. Aggregation runs in F# on `decimal`

- **Decision**: load the user's non-transfer transactions in the period (joined
  to their tags) and aggregate with a pure function. Do not use SQL `SUM`.
- **Why**: SQLite sums in floating point, and the money rule is that all
  aggregation uses the backend `decimal`. A year of personal transactions is
  small enough to load.
- **Goal**: one tested function owns the income statement rules; the handler
  only queries and maps.
- **Ownership**: the function lives in the slice. It moves to `Domain/` when a
  second slice needs it: snapshots or the dashboard slice (decision 10),
  whichever comes first.

### 6. Month to date is the default period

- **Decision**: the default preset is "This month" (the first of the month up to
  `today`). The other presets are "Last month", "Last 28 days" (`today - 27` to
  `today`), "Last 365 days" (`today - 364` to `today`), and "This financial
  year" (from 1 April). The chosen preset is saved to localStorage, the one kind
  of data the client keeps there (preferences, never server data).
- **Why**: monthly periods are the default in budgeting tools and match bills,
  statements, and monthly budgets. An income statement covers a fixed reporting
  period, not a rolling one. A month-to-date figure only changes when
  transactions are added, while a rolling window changes as old days leave it,
  and monthly items (rent, a monthly salary) leave a 28-day window for a few
  days each month.
- **Known weakness**: early in the month the figures are small and say little on
  their own. The fix is a baseline comparison (decision 12), not a different
  default window.
- **Period arithmetic**: a pure client module that takes `today` and a preset
  and returns `from`/`to`, with unit tests for month ends, leap years, and year
  boundaries. The previous project had two versions of "last twelve months", one
  of which gets the range wrong in January. Moves to the server with the full
  dashboard (decision 11).
- **Goal**: every figure on the page covers the same, explicitly labelled
  period. The previous project mixed 28-day, calendar month, and trailing
  twelve-month figures on one page.

### 7. Separate endpoints, no dashboard aggregate

- **Decision**: the page calls `GET /api/balance-sheet` and `GET
  /api/income-statement`. There is no `/api/dashboard`.
- **Why**: slices do not import each other, and a dashboard endpoint would need
  both. Changing the period only re-requests the income statement.
- **Goal**: each slice stays independent, and the page composes them.
- **Replaced** by decision 10 when the full dashboard is built.

### 8. No charts in the MVP

- **Decision**: the MVP shows figures and tables only.
- **Why**: "Full dashboard w/ charts" is a separate roadmap item. The previous
  project's dashboard grew to about 4,000 lines of charts, cards, and statistics
  before the underlying figures were settled.
- **Goal**: settle the income statement rules first, then build charts on them.
- **Replaced** by decisions 14 and 15 when the full dashboard is built.

## MVP consequences

- **Tag kind is required.** Every tag has a `Kind`; the tag form asks for it.
- **Response shape.** The income statement carries its period, the three totals,
  and the income and expense lines. Expense lines also carry their share.
  Untagged lines have no tag id or colour. Lines are sorted by amount, largest
  first, with the untagged line last. Field docs are in the OpenAPI document.
- **Empty states.** A period with no transactions shows a link to the
  transactions page. An empty balance sheet is an empty state with a link to the
  balance sheet page, as on that page. Transactions waiting for a tag get a
  muted note below the statement with a link to quick tagging, not a warning:
  some transactions are left untagged on purpose. The note counts the whole
  quick tagging queue, whatever the period, so it matches the page it links to
  ([quick tagging](quick-tagging.md) decision 7).
- **Route.** The dashboard is the `/` route.
- **Client read shapes.** The dashboard page decodes only the balance sheet
  fields it shows, and only the quick tagging queue's total, with its own
  decoders, rather than importing the other pages'.
- **Highest-value tests.** The income statement rules (refunds, negative expense
  lines, clawbacks, the untagged split, shares, rounding) and the period
  arithmetic (month ends, leap years, year boundaries).

## Full dashboard

Planned, not built. It waits on the snapshots roadmap item, which provides the
balance sheet as of a date and settles shared periods and statement code. Where
a decision below depends on how snapshots turn out, it says so.

### 9. The page answers four questions with as little as possible

- **Decision**: the page answers the questions a financial planner answers for a
  client, each with the fewest figures that do it:

  | Question                                  | Section  | Shows                                                                                                 |
  | ----------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------- |
  | Where do I stand?                         | Position | Net worth, working capital, runway, the oldest as-of date among the lines                             |
  | Am I saving?                              | Period   | Income, expenses, net income, savings rate, each against its baseline                                 |
  | Where does the money go; what is unusual? | Period   | Income and expense lines, each against its baseline; expense lines with an inline bar for their share |
  | Is this consistent?                       | History  | A cash flow chart (income and expenses per month, net income) and a net worth chart (month ends)      |

- **Why**: planners report a net worth statement, a cash flow statement, and a
  few standard ratios, chiefly the savings rate and the emergency fund
  (liquidity) ratio, which runway is. Consumer apps (Monarch, Copilot, YNAB)
  centre on cash flow bars, net worth over time, and spending against a budget
  or a typical month. The app has no budgets; the baseline stands in for one.
- **Rejected**:
  - A spending pace chart (cumulative spending by day against the baseline). The
    period's expenses against the same days of earlier periods give the same "on
    track" signal as one figure, and the lines show whether a gap is timing
    (rent paid early) or spending.
  - A tag by month table and stacked bars of expenses by tag. The lines against
    their baseline already show what is unusual. Stacked bars of 10 to 15
    user-chosen colours cannot be read, and stacking would sum money on the
    client.
  - A pie or donut of expenses. The share bars do this with less space and are
    easier to compare.
  - Debt ratios. Debt to assets adds little next to net worth for one person,
    and debt service ratios need loan repayments, which are not modelled.
  - Net worth history rebuilt by subtracting transactions from current balances,
    as the previous project did. It is only correct if every account's
    transactions are imported. Snapshots give the real figures.
- **Goal**: each figure on the page answers a question the user has, and the
  page grows by two figures, one comparison per figure and line, and two charts.

### 10. A read-only dashboard slice serves the page

- **Decision**: `Feature/Dashboard/` is a read-only slice with one endpoint per
  group of figures that change together:
  - **Period**: depends on the preset. The income statement for the period,
    savings rate, the baseline for each total and line, how many baseline
    periods it averages, and the latest transaction date.
  - **History**: does not depend on the preset. Today's position and runway, the
    twelve months of history, and averages over the complete months.

  The page keeps calling the quick tagging queue for its total. `GET
  /api/income-statement` and `GET /api/balance-sheet` are no longer called by
  the dashboard and stay single purpose for their own pages and for snapshots.
- **Why**: the figures combine both statements (runway divides a balance sheet
  figure by an income statement figure) and earlier periods (baselines). Doing
  that in the statement endpoints would make each of them do several jobs, and
  doing it on the client would put money arithmetic there. Decision 7 rejected a
  dashboard endpoint because slices do not import each other; shared code
  removes that reason. The dashboard slice uses `Domain/` for the balance sheet,
  the income statement computation (moved there per decision 5), and the
  snapshot query.
- **Replaces** decision 7.
- **Goal**: the client only displays figures, the statement endpoints stay
  single purpose, and changing the preset re-requests one endpoint.

### 11. The server works out periods from the preset and the client's `today`

- **Decision**: the period endpoint takes the preset and `today`; the history
  endpoint takes `today`. The server turns them into the period, the baseline
  periods, and the months of history. The client keeps the preset in
  localStorage and its labels; the client period module and its tests move to
  the slice.
- **Why**: the baseline periods (decision 12) depend on the preset's shape, and
  belong next to the preset rules. Sending `today` keeps decision 4's property:
  the period follows the client's calendar and the server needs no timezone
  ([dates.md](dates.md)). Sending a list of baseline periods from the client was
  the alternative; it spreads one rule across both sides.
- **Replaces** the period arithmetic in decision 6 and, for the dashboard,
  decision 4.
- **Goal**: one tested module owns every period on the page.

### 12. The baseline is the mean of the same days in earlier periods

- **Decision**: a period's baseline is the mean of the same figure over earlier
  periods of the same shape: at most 12, each starting no more than a year
  before the period. By preset:

  | Preset              | Earlier periods                              | Count |
  | ------------------- | -------------------------------------------- | ----- |
  | This month          | The same days of each earlier month          | 12    |
  | Last month          | Each earlier whole month                     | 12    |
  | Last 28 days        | Each earlier 28-day window                   | 12    |
  | Last 365 days       | The 365 days before                          | 1     |
  | This financial year | The same days of the previous financial year | 1     |

  Moving by months keeps the day of the month and clamps it to the target
  month's length, and a period ending on a month's last day maps to the target
  month's last day: 1 to 30 March maps to 1 to 28 February, and the whole of
  September maps to the whole of August. Earlier periods that start before the
  user's first transaction are dropped; with none left, the page shows that the
  baseline is still building. Lines are the union of the period's and the
  baseline's tags, so a usual expense with nothing spent this period still
  shows. Each total and line carries its baseline and its change from it, as an
  amount and a percentage.
- **Why**: a figure needs a baseline to be read, and comparing part of a period
  with whole periods misleads: on the 14th, a month to date looks cheap next to
  an average month. Same days compare like with like. A mean of several periods
  is less noisy than the previous period alone. The one-year limit keeps
  year-long presets from averaging over a decade. The previous project's
  expenses-by-tag cards compared the last complete month with the mean of
  earlier months for the same reason.
- **Goal**: every period figure reads as "this, against what is typical for
  these days".

### 13. Savings rate and runway are computed on the server

- **Decision**:
  - Savings rate is net income divided by income, as a percentage. None when
    income is zero or negative.
  - Runway is working capital divided by average monthly expenses over the
    complete months of the history. None when there is no complete month or the
    average is zero or negative; zero when working capital is negative.
  - Both are computed in `decimal` in the dashboard slice, and the period's
    savings rate has a baseline like the other figures.
- **Why**: savings rate is the planner's main flow ratio, and runway the
  emergency fund ratio (a common target is three to six months). Runway uses
  working capital rather than liquid assets, so short-term debts count against
  it. The savings rate is on take-home pay, since the app sees bank
  transactions: contributions taken out of pay (e.g. KiwiSaver) are not in it,
  and the page says so.
- **Goal**: the two ratios planners lead with, with no money arithmetic on the
  client.

### 14. History covers twelve complete months plus this month

- **Decision**: the history section always covers the last twelve complete
  months and the current month to date, whatever the preset, and is labelled so.
  Each month has income, expenses, net income, and month-end net worth and
  working capital (today's for the current month). Averages use complete months
  only. Two charts show it: cash flow (income and expense bars per month with a
  net income line) and net worth (a line). The current month is drawn as
  partial. Each chart has its data as a table below it.
- **Why**: twelve months show seasonality and the direction of travel without a
  range picker, and their complete months are the denominator for runway. The
  section has its own explicitly labelled window, so decision 6's goal (every
  figure says which period it covers) still holds.
- **Snapshots**: the month-end balances come from the snapshot query. If a
  snapshot is the balance sheet at a period's end plus the income statement for
  the period, the history is the last twelve monthly snapshots and this month so
  far.
- **Replaces** decision 8.
- **Goal**: one look shows whether saving and net worth are steady, rising, or
  falling.

### 15. Charts use Observable Plot in a custom element

- **Decision**: charts are drawn by Observable Plot inside a custom element
  defined in client FFI, as the modal dialog is. The page passes the chart's
  figures as a property; the element redraws when they change. The element is
  loaded only on the dashboard. The client only scales server figures to pixels;
  it never sums, stacks, or accumulates them.
- **Why**: Plot is a function from data to SVG, so a chart holds no state for
  the model to keep in step, which suits MVU. Its SVG follows `currentColor` and
  the page font, so dark mode works through Tailwind. It has sound default
  scales and ticks, and tooltips. Sizes measured in October 2026 for a bar and
  line chart (minified, gzipped; the whole client was 44K):

  | Library                     | Size | Rejected because                                                            |
  | --------------------------- | ---- | --------------------------------------------------------------------------- |
  | uPlot                       | 22K  | Time series only, canvas, low level                                         |
  | Chart.js                    | 58K  | Canvas, a chart instance to update, dark mode by config                     |
  | Observable Plot             | 90K  | Chosen                                                                      |
  | ECharts (bar and line only) | 190K | A chart instance to create, update, and dispose, with theme handling        |
  | ApexCharts                  | 269K | Larger, no advantage                                                        |
  | Vega-Lite                   | 282K | Largest; evaluates expressions with `new Function`, which a CSP would block |
  | Hand-written SVG in Lustre  | 0K   | Axes, ticks, and tooltips are a library's worth of work                     |

  ECharts is the fallback if zooming or toggling series is ever needed.
- **Goal**: charts are a pure view of server figures, with no chart state in the
  model.

### 16. The page shows how fresh the data is

- **Decision**: the period section shows the latest transaction date in the
  period, and the position section the oldest as-of date among the balance sheet
  lines.
- **Why**: bank exports lag a few days, so a month to date compared with the
  same days of earlier months looks cheap until the next import. Balances are
  set by hand or by import and can be weeks old, and runway inherits that.
- **Goal**: the user can tell a low figure from missing data.

## Full dashboard consequences

- **Routes and shapes.** The dashboard endpoints live under `/api/dashboard/`.
  Field docs are in the OpenAPI document. The page decodes them with its own
  decoders, as now.
- **Quick tagging note.** Unchanged (MVP consequences).
- **Highest-value tests.** The baseline periods for each preset (month ends,
  leap years, financial year boundaries, the first-transaction cutoff), the
  baseline means and the line union, the ratios' none and zero cases, and the
  monthly buckets. One E2E test drives the page through both sections.

## Deferred

- **Shortening baselines to the data.** Comparing only up to the latest
  transaction date would remove the import lag from the comparison (decision
  16). Revisit if the caption is not enough.
- **Spending pace chart.** Rejected for now (decision 9). Revisit if the period
  comparison proves too coarse.
- **A tag's history.** A drill-down from a line to that tag's months and
  transactions, alongside transaction search.
- **Excluded tags.** The transfer categorisation covers the main use (internal
  transfers). Revisit if another use appears.

## Assumptions

- Single base currency, as in [balance-sheet.md](balance-sheet.md).
- Every tag is either income or expense. Transfers are excluded by their
  categorisation, not by tag.
