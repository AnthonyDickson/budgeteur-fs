# Dashboard

Design brief for the dashboard. It records what we decided, why, and what each
decision is meant to achieve, so later changes have one written source of
intent. Change it when the reasoning changes.

The brief has two parts, both built: the [MVP](#mvp-decisions), and the
[full dashboard](#full-dashboard), which builds on [reports](reports.md). Where
the full dashboard replaces an MVP decision, both decisions say so.

The previous Rust project (`budgeteur`, `server/src/dashboard/`) built two
dashboards: an HTML page with charts, summary tables, and expenses-by-tag cards,
and a JSON/TUI view with net worth history, net income, spending pace, and
savings runway. Lessons from it are cited where they shaped a decision.

## Goal

Give the user one page that answers two questions:

- **Where do I stand?** Net worth and working capital, from the balance sheet.
- **Where did my money go this period?** Income, expenses, and net income for a
  date range, with expenses broken down by tag.

The MVP shows figures and tables only, for a period chosen from presets. The
full dashboard covers the current month only, and adds comparisons against a
baseline, two ratios, and twelve months of history with charts. Other periods
are on the reports page.

## Ubiquitous language

| Term             | Meaning                                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| Period           | An inclusive `from`/`to` pair of calendar dates. See [dates.md](dates.md).                                  |
| Preset           | MVP only. A named rule that turns the client's `today` into a period, e.g. "This month".                    |
| `TagKind`        | `Income` or `Expense`. Set by the user on each tag. Decides which side of the income statement a tag is on. |
| Income statement | Income, expenses, and net income for a period, broken down into lines.                                      |
| Line             | One tag's net amount for the period, or the untagged income or untagged expenses.                           |
| Net income       | Income minus expenses.                                                                                      |
| Net worth        | As in [balance-sheet.md](balance-sheet.md).                                                                 |
| Working capital  | As in [balance-sheet.md](balance-sheet.md).                                                                 |
| Month to date    | The first of the current calendar month up to the client's `today`. The full dashboard's period.            |
| Baseline         | The mean of a figure over the same days of earlier months. What "typical" means on the page.                |
| Baseline months  | The history's complete months that start on or after the user's first transaction. At most twelve.          |
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
  flow side now means later reports extend it rather than rename it.
- **Goal**: the dashboard is a composition of domain statements, not a bespoke
  aggregate that only the dashboard understands.
- **Full dashboard**: both statements are still computed from the shared code,
  but one dashboard read serves the page, and the income statement slice is
  removed (decision 10).

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
  at most two years (731 days), long enough for the full dashboard's history
  (decision 14). Every failure is reported in one `400`.
- **Goal**: no server timezone for the MVP, and endpoint tests are
  deterministic.
- **Full dashboard**: the dashboard endpoint takes `today` only (decision 11),
  and `GET /api/income-statement` is removed (decision 10).

### 5. Aggregation runs in F# on `decimal`

- **Decision**: load the user's non-transfer transactions in the period (joined
  to their tags) and aggregate with a pure function. Do not use SQL `SUM`.
- **Why**: SQLite sums in floating point, and the money rule is that all
  aggregation uses the backend `decimal`. A year of personal transactions is
  small enough to load.
- **Goal**: one tested function owns the income statement rules; the handler
  only queries and maps.
- **Ownership**: the function and its period live in `Domain/`, since the report
  slice uses them too ([reports](reports.md) decision 7). The slice keeps the
  query and the response.

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
  of which gets the range wrong in January.
- **Goal**: every figure on the page covers the same, explicitly labelled
  period. The previous project mixed 28-day, calendar month, and trailing
  twelve-month figures on one page.
- **Replaced** by decision 11 when the full dashboard is built: the page covers
  the month to date only, and the presets, their preference, and the client
  period module are removed.

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

Built on [reports](reports.md), which provide the balance sheet for a statement
date, reporting periods, savings rate, and the shared statement code in
`Domain/` and `Data/`.

### 9. The page answers four questions with as little as possible

- **Decision**: the page answers the questions a financial planner answers for a
  client, each with the fewest figures that do it:

  | Question                                  | Section  | Shows                                                                                                 |
  | ----------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------- |
  | Where do I stand?                         | Position | Net worth, working capital, runway, the oldest as-of date among the lines                             |
  | Am I saving?                              | Month    | Income, expenses, net income, savings rate, each against its baseline                                 |
  | Where does the money go; what is unusual? | Month    | Income and expense lines, each against its baseline; expense lines with an inline bar for their share |
  | Am I saving, over a year?                 | History  | Income, expenses, net income, and savings rate over the baseline months, with monthly averages        |
  | Is this consistent?                       | History  | A cash flow chart (net income per month) and a net worth chart (month ends)                           |

- **Why**: planners report a net worth statement, a cash flow statement, and a
  few standard ratios, chiefly the savings rate and the emergency fund
  (liquidity) ratio, which runway is. Consumer apps (Monarch, Copilot, YNAB)
  centre on cash flow bars, net worth over time, and spending against a budget
  or a typical month. The app has no budgets; the baseline stands in for one.
- **Rejected**:
  - A spending pace chart (cumulative spending by day against the baseline). The
    month's expenses against the same days of earlier months give the same "on
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
    transactions are imported. Observation histories give the real figures.
  - Change in net worth and other changes per month. They are the reports page's
    question ([reports](reports.md) decision 6); the net worth chart beside the
    net income line shows the trend.
- **Goal**: each figure on the page answers a question the user has, and the
  page grows by two figures, one comparison per figure and line, the history's
  totals, and two charts.

### 10. One read-only dashboard read serves the page

- **Decision**: `Feature/Dashboard/` is a read-only slice with one operation:
  the dashboard for the client's `today`. It returns today's position and
  runway; the month to date's income statement and savings rate, the baseline
  for each total and line, how many baseline months it averages, and the latest
  transaction date in the month; and the history with its totals. The page keeps
  calling the quick tagging queue for its total, and no longer calls `GET
  /api/balance-sheet`. `GET /api/income-statement` and its slice are removed:
  the dashboard was its only caller, and reports and the dashboard compute
  statements from the shared code.
- **Why**: the figures combine both statements (runway divides a balance sheet
  figure by an income statement figure) and earlier months (baselines). Doing
  that in the statement endpoints would make each of them do several jobs, and
  doing it on the client would put money arithmetic there. Decision 7 rejected a
  dashboard endpoint because slices do not import each other; the code reports
  moved to `Domain/` and `Data/` removes that reason. With one period
  (decision 11) nothing on the page changes on its own, so one read suffices,
  and the baseline months are the history's complete months, so the same
  transactions and observations serve every figure. An earlier plan had a period
  read and a history read, so that changing the preset re-requested only the
  period figures; without presets there is nothing to split for.
- **Replaces** decision 7.
- **Goal**: the client only displays figures, the statement endpoints stay
  single purpose, and the page makes one read for its figures.

### 11. The dashboard covers the month to date; reports cover other periods

- **Decision**: the page's period is the month to date: the monthly reporting
  period containing the client's `today`, up to `today`, as a monthly report to
  date has. The page has no preset picker and keeps no preference. The server
  works out the month, the baseline months, and the history months from `today`
  with the shared reporting period code.
- **Why**: the presets now repeat the reports page. "Last month" is its default
  monthly report, and "This financial year" is the financial year report to
  date. The rolling windows go against decision 6's own reasoning (an income
  statement covers a fixed period, and monthly items leave a 28-day window), and
  the history's twelve months cover a trailing year. The reports brief already
  places the current month on the dashboard ([reports](reports.md) decision 8).
  Keeping presets would keep a baseline rule per preset, a preference, a second
  read, and period arithmetic for windows no other code uses. Sending `today`
  keeps decision 4's property: the period follows the client's calendar and the
  server needs no timezone ([dates.md](dates.md)).
- **Early in the month**: the month to date is small for the first days. Its
  baseline covers the same few days (decision 12), and the history shows last
  month whole.
- **Replaces** decision 6 and, for the dashboard, decision 4. The client period
  module, its tests, and the preset preference are removed.
- **Goal**: the dashboard is about now, the reports page about any period, and
  one tested module owns every period on both.

### 12. The baseline is the mean of the same days in earlier months

- **Decision**: a figure's baseline is its mean over the same days of each
  baseline month: from the first of that month to today's day of the month. The
  day is clamped to the month's length, and on a month's last day it maps to the
  other month's last day: on 30 March the February days are 1 to 28, and on 30
  September the whole of August is used. Baseline months are the history's
  complete months that start on or after the user's first transaction, so a
  month the user has partial data for is not averaged; with none, the page shows
  that the baseline is still building. Lines are the union of the month's and
  the baseline's tags, so a usual expense with nothing spent this month still
  shows. Each total and line carries its baseline and its change from it, as an
  amount and a percentage; the percentage is none when the baseline is zero or
  negative. The savings rate's baseline is the savings rate of the baseline
  income and net income, not the mean of each month's rate. Its change is in
  percentage points (decision 17).
- **Why**: a figure needs a baseline to be read, and comparing part of a month
  with whole months misleads: on the 14th, a month to date looks cheap next to
  an average month. Same days compare like with like. A mean of several months
  is less noisy than the previous month alone. A mean of monthly rates would let
  a month with little income swing the baseline, and would have to skip months
  with no income; the rate of the means is the rate over the baseline months
  taken together. The previous project's expenses-by-tag cards compared the last
  complete month with the mean of earlier months for the same reason.
- **Goal**: every figure for the month reads as "this, against what is typical
  for these days".

### 13. Savings rate and runway are computed on the server

- **Decision**:
  - Savings rate follows the shared rule reports use: net income divided by
    income, as a percentage, none when income is zero or negative.
  - Runway is working capital divided by average monthly expenses, the mean of
    the baseline months' whole-month expenses. None when there is no baseline
    month or the average is zero or negative; zero when working capital is
    negative. It is computed in `decimal` in the dashboard slice.
- **Why**: savings rate is the planner's main flow ratio, and runway the
  emergency fund ratio (a common target is three to six months). Runway uses
  working capital rather than liquid assets, so short-term debts count against
  it. It averages the baseline months rather than every history month, so a
  first month with partial data does not understate expenses and overstate
  runway. The savings rate is on take-home pay, since the app sees bank
  transactions: contributions taken out of pay (e.g. KiwiSaver) are not in it,
  and the page says so.
- **Goal**: the two ratios planners lead with, with no money arithmetic on the
  client.

### 14. History covers twelve complete months plus this month

- **Decision**: the history section covers the last twelve complete months and
  the month to date, and is labelled so. It starts no earlier than the month
  containing the user's first observation or transaction, where reports start
  ([reports](reports.md) decision 5). Each month has income, expenses, net
  income, and net worth and working capital as of its last day (`today` for the
  current month). Two charts show it: cash flow (a net income bar per month,
  above or below zero) and net worth (a line). The current month is drawn as
  partial. Each chart has its data as a table below it, which also has each
  month's income and expenses. The tables start collapsed, to keep the section
  to its charts and totals; the cash flow chart's tooltips also show a month's
  income and expenses.
- **Totals**: above the charts, income, expenses, net income, and savings rate
  over the baseline months taken together, with income, expenses, and net income
  also as monthly averages. The section is labelled with the months they cover,
  e.g. "Last 7 months" for a user with seven baseline months. The savings rate
  is net income over income for the whole span, as for the baseline (decision
  12). The average monthly expenses are runway's denominator (decision 13), so
  the page shows the figure runway divides by.
- **Why**: twelve months show seasonality and the direction of travel without a
  range picker, and their complete months are the baseline months. A single
  month is noisy, with irregular income and annual bills; the totals give the
  year's answer to "am I saving?". The month to date is excluded from them since
  a partial month would pull every total and average down, and a first month
  with partial data is excluded for the same reason. The section has its own
  explicitly labelled window, so decision 6's goal (every figure says which
  period it covers) still holds.
- **Cash flow as net income only**: the chart first had income and expense bars
  with a net income line. The line was hard to see against the bars, and three
  marks per month crowded the tooltips. Net income is the figure that answers
  "is this consistent?", and the table keeps income and expenses. Bars suit a
  monthly flow and keep it apart from net worth, a stock, drawn as a line.
- **Reports**: each month's figures are its monthly report's: the income
  statement for the month and the balance sheet drawn for its closing date, from
  the same shared code. The report itself, with its opening sheet and other
  changes, stays in the report slice.
- **Replaces** decision 8.
- **Goal**: one look shows whether saving and net worth are steady, rising, or
  falling.

### 15. Charts use Observable Plot in a custom element

- **Decision**: charts are drawn by Observable Plot inside a custom element
  defined in client FFI, as the modal dialog is. The page passes the chart's
  figures as a property; the element redraws when they or its width change. Plot
  is loaded when the element first draws, so only the dashboard fetches it. The
  client only scales server figures to pixels; it never sums, stacks, or
  accumulates them.
- **Why**: Plot is a function from data to SVG, so a chart holds no state for
  the model to keep in step, which suits MVU. Its SVG follows `currentColor` and
  the page font, and it takes CSS variables as colours, so the charts follow
  dark mode ([styling](styling.md) decision 10). It has sound default scales and
  ticks, and tooltips. Sizes measured in October 2026 for a bar and line chart
  (minified, gzipped; the whole client was 44K):

  | Library                     | Size | Rejected because                                                            |
  | --------------------------- | ---- | --------------------------------------------------------------------------- |
  | uPlot                       | 22K  | Time series only, canvas, low level                                         |
  | Chart.js                    | 58K  | Canvas, a chart instance to update, dark mode by config                     |
  | Observable Plot             | 90K  | Chosen                                                                      |
  | ECharts (bar and line only) | 190K | A chart instance to create, update, and dispose, with theme handling        |
  | ApexCharts                  | 269K | Larger, no advantage                                                        |
  | Vega-Lite                   | 282K | Largest; evaluates expressions with `new Function`, which a CSP would block |
  | Hand-written SVG in Lustre  | 0K   | Axes, ticks, and tooltips are a library's worth of work                     |

  ECharts is the fallback if zooming or toggling series is ever needed. The same
  element serves a line's balance chart on its details page, which reports
  deferred.
- **Goal**: charts are a pure view of server figures, with no chart state in the
  model.

### 16. The page shows how fresh the data is

- **Decision**: the month section shows the latest transaction date in the
  month, and the position section the oldest as-of date among the balance sheet
  lines.
- **Why**: bank exports lag a few days, so a month to date compared with the
  same days of earlier months looks cheap until the next import. Balances are
  set by hand or by import and can be weeks old, and runway inherits that.
- **Goal**: the user can tell a low figure from missing data.

### 17. The month section highlights improvements

- **Decision**:
  - Each total and line shows this month's amount, its baseline, and the change
    as an amount and a percentage, whatever the size of the baseline. The
    savings rate's change is in percentage points instead, e.g. "−7 pts": a
    percentage of a percentage reads badly.
  - A change is green when it is an improvement: a decrease in expenses or an
    expense line, an increase in income, an income line, net income, or the
    savings rate. Other changes are not coloured. The sign carries the
    direction, so the colour is not the only cue.
  - Lines are sorted by this month's amount, largest first, with the untagged
    line last, as in the MVP. A usual expense with nothing spent this month sits
    at the bottom of its side.
  - Each expense line's share bar is a thin strip below the line, so the amount,
    baseline, and change columns have the width and the table stays about as
    tall as one row per line.
  - On a phone (below `sm`) the line tables drop the baseline and percentage
    columns, keeping the amount and the change in amount, so the tag's name has
    room. The total cards above keep all three figures.
- **Why**: showing every percentage is the simplest rule, and a large percentage
  on a small baseline is visibly small in its amount column. Highlighting only
  improvements keeps the side's direction out of the colour rule's way: one
  colour means "better than typical" on both sides. Sorting by amount keeps the
  share bars in order, and the baseline column still shows a usual expense that
  has not been paid yet.
- **Goal**: the month section reads at a glance, with one meaning per colour.

## Full dashboard consequences

- **Route and shape.** The dashboard read is `GET /api/dashboard`, taking
  `today`. Field docs are in the OpenAPI document. The page decodes it with its
  own decoders, as now.
- **Removed.** `GET /api/income-statement` and its slice, the dashboard's
  balance sheet read, the client period module and its tests, and the preset
  preference.
- **Quick tagging note.** Unchanged (MVP consequences).
- **Highest-value tests.** The baseline days (clamping, month ends, leap years,
  year boundaries) and baseline months (the first-transaction cutoff, fewer than
  twelve), the baseline means and the line union, the savings rate baseline,
  runway's none and zero cases, the history months (the first data cutoff, the
  month to date), and the history totals over fewer than twelve months. One E2E
  test drives the page through its three sections.

## Deferred

- **Shortening baselines to the data.** Comparing only up to the latest
  transaction date would remove the import lag from the comparison (decision
  16). Revisit if the caption is not enough.
- **Spending pace chart.** Rejected for now (decision 9). Revisit if the month
  comparison proves too coarse.
- **Opening a month's report from the history.** Needs a reports route that
  carries the frequency and a date; the reports page has no such route yet.
- **Percentages on small baselines.** Shown whatever the baseline's size
  (decision 17). Revisit if they prove noisy, e.g. by omitting the percentage
  below a share of the side's total.
- **Other periods on the dashboard.** Decision 11 leaves them to reports.
  Revisit if a rolling window is wanted that no reporting period covers.
- **A tag's history.** A drill-down from a line to that tag's months and
  transactions, alongside transaction search.
- **Excluded tags.** The transfer categorisation covers the main use (internal
  transfers). Revisit if another use appears.

## Assumptions

- Single base currency, as in [balance-sheet.md](balance-sheet.md).
- Every tag is either income or expense. Transfers are excluded by their
  categorisation, not by tag.
