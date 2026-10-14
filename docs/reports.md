# Reports

Design brief for reports: the balance sheet and income statement for regular
periods, and the observation history they need. It records what we decided, why,
and what each decision is meant to achieve, so later changes have one written
source of intent. Change it when the reasoning changes.

Reports build on the [balance sheet](balance-sheet.md), the income statement
([dashboard](dashboard.md)), and account balance observations
([CSV import](csv-import.md) decision 3). The
[full dashboard](dashboard.md#full-dashboard) is planned on top of them.

## Goal

Show the user how their position and performance change over time:

- **How has my net worth changed, and why?** The change in net worth over a
  period, split into what was saved (net income) and everything else
  (revaluations, money that never passes through a tracked account, missing
  transactions).
- **How did each period go?** Income, expenses, net income, and savings rate for
  each month, quarter, or year.

## Ubiquitous language

| Term                  | Meaning                                                                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Report                | The position and performance for one reporting period: the opening and closing balance sheets, the income statement, and the change in net worth.                        |
| Reporting period      | A period aligned to a frequency: a calendar month, a quarter, a calendar year, or a financial year.                                                                      |
| Frequency             | `Monthly`, `Quarterly`, `CalendarYear`, or `FinancialYear`.                                                                                                              |
| Financial year        | 1 April to 31 March, labelled by both years, e.g. 2026/27.                                                                                                               |
| Complete              | A reporting period whose last day is on or before the client's `today`. A report for a period that is not complete is to date.                                           |
| Opening balance sheet | The balance sheet as of the day before the period starts. The previous report's closing balance sheet.                                                                   |
| Closing balance sheet | The balance sheet as of the period's last day, or as of `today` for a report to date.                                                                                    |
| Change in net worth   | Closing net worth minus opening net worth.                                                                                                                               |
| Other changes         | Change in net worth minus net income: revaluations, money that never passes through a tracked account (e.g. employer KiwiSaver contributions), and missing transactions. |
| Line                  | An item or an account: anything on the balance sheet. As in [balance-sheet.md](balance-sheet.md).                                                                        |
| Observation           | A line's value (item) or balance (account) as of a date. Accounts have had them since CSV import; items now have them too.                                               |
| Observation history   | A line's observations.                                                                                                                                                   |
| Closed                | A line the user no longer has (sold, repaid, account closed), from its close date on.                                                                                    |
| Statement date        | As in [balance-sheet.md](balance-sheet.md): the date a balance sheet is drawn for.                                                                                       |

"Snapshot" is not a term. Earlier briefs used it both for the balance sheet as
of a date, which is the balance sheet drawn for a statement date, and for the
periodic package, which is a report.

"Line" also names a line of the income statement. The statement it belongs to is
always clear from context; where it is not, say "balance sheet line".

## Decisions

### 1. Reports are queried, not stored

- **Decision**: a report is computed when it is read, from the observations and
  transactions as they are now. Nothing is stored per period.
- **Why**: late imports and corrections then reach past reports without a
  rebuild, and no scheduled job or server timezone is needed: the client sends
  its `today` ([dates.md](dates.md)). Stored reports would keep a mistake until
  rebuilt, and would need both.
- **Consequence**: a past report changes when its data changes. That is the
  intent: a report shows the best current knowledge of the period.
- **Goal**: one source of truth, the observations and transactions, with every
  report derived from it.

### 2. Every line's balance is an observation

- **Decision**: items get observations: an item, an as-of date, and a
  non-negative value, at most one per item and date. The item no longer stores a
  value and as-of date of its own; its current value is its latest observation.
  Recording an observation on a date that has one replaces it, as for accounts.
- **Why**: a balance sheet for a past date needs each line's balance at that
  date, and an item that keeps only its latest balance has no past. The CSV
  import brief chose this for items when it introduced account observations.
- **Separate tables**: item observations are magnitudes and account observations
  are signed ([balance sheet](balance-sheet.md) decisions 3 and 5), so each has
  its own table. One table with either an item or an account reference was
  rejected: the reference cannot be a plain foreign key, and the sign rule would
  depend on which column is set.
- **Goal**: items and accounts have the same observation history, recorded and
  corrected the same way.

### 3. The balance sheet is drawn for a statement date

- **Decision**: in a balance sheet drawn for a statement date, each line's
  balance is its latest observation on or before that date, shown with the
  observation's date. A line enters the sheet at its first observation: before
  it, the line is left out, not shown as unknown. An account with no
  observations at all is listed as unknown, as now. A line closed on or before
  the statement date is left out (decision 4). The balance sheet page is
  unchanged: it shows each line's latest observation.
- **Why**: [balance sheet](balance-sheet.md) decision 4 made the statement date
  the date the sheet is drawn for, so a past sheet is the same read for an
  earlier date. Listing every later account as unknown on each past sheet would
  bury the lines that matter. Balances between observations are not
  interpolated, which would invent figures; a line valued once a year keeps its
  value until the next observation, and its date shows how old it is.
- **Computation**: a pure function in `Domain/` picks each line's observation
  for the date from the user's observations, as the income statement aggregates
  loaded transactions ([dashboard](dashboard.md) decision 5). A user's
  observations are small enough to load. The current balance view stays for
  reads that only need each account's latest balance.
- **Goal**: one computation for every report's sheets and the dashboard's
  history.

### 4. Lines are closed, not deleted

- **Decision**: items and accounts get an optional close date, set and cleared
  in their edit forms. A sheet drawn on or after the close date leaves the line
  out; earlier sheets keep it. A close date later than the server's UTC date
  plus one day is rejected, as for as-of dates, so the current sheet leaves out
  every closed line without knowing the client's today. The balance sheet page
  lists closed lines in a collapsed section, so they can be reopened or viewed.
  Deleting stays for mistakes, and removes the line's balance history.
- **Transactions after the close date**: a closed account with transactions
  dated after its close date is flagged in the closed section, which opens to
  show the flag. Transactions on the close date are the account's last, so they
  are not flagged. The flag is worked out when the sheet is read, and the user
  corrects the close date in the account's edit form.
- **Why**: deleting a sold or repaid line removes it from every past sheet and
  changes past net worth. A close date is one stored fact. The CSV import brief
  planned a final $0 observation instead; that needs a convention to tell a
  closing $0 from a balance of $0, which an empty account has. A transaction
  after the close date means the close date is likely wrong, but reopening the
  account on import was rejected: it would silently change every report after
  that date. The import summary was rejected as the place for the flag, since
  the flag would be lost with it.
- **Goal**: past reports stay correct after a line is sold, repaid, or closed,
  and the current sheet only shows lines the user has.

### 5. Reporting periods follow the calendar

- **Decision**: four frequencies: calendar months, quarters (January to March,
  and so on), calendar years, and financial years from 1 April. A frequency's
  reports run from the period containing the user's first observation or
  transaction, whichever is earlier, to the period containing `today`, which is
  to date.
- **Why**: monthly and quarterly reviews and annual figures are how planners and
  banks report. New Zealand's financial year starts on 1 April, and the
  dashboard's "This financial year" preset already assumes it. Its quarters are
  the calendar quarters, so one set of quarters serves both years.
- **Goal**: periods the user already thinks in, with no setup.

### 6. A report pairs two balance sheets with the income statement

- **Decision**: a report carries its period, whether it is complete, opening and
  closing net worth and working capital, the changes in both, net income, other
  changes, savings rate, the income statement, and the closing balance sheet.
  The income statement and savings rate follow the [dashboard](dashboard.md)
  rules (decisions 3 and 13). The opening balance sheet appears only as its
  totals: the change in net worth and its split give what changed, as published
  statements give the closing position and the movement. The first report's
  opening balance sheet is empty when no line has an observation before the
  period; its changes and other changes are then shown as not meaningful, since
  each change would be the whole closing figure.
- **Why**: the change in net worth says how wealth moved, and net income says
  how much of that was saved; other changes are the rest. Planners present this
  as a statement of changes in net worth. A month with $3k saved and $8k more
  net worth had $5k of revaluations or contributions the transactions do not
  show, and a large negative other change can mean missing transactions.
- **Goal**: each report answers "how much did I save, and how much did my net
  worth change".

### 7. A read-only report slice; the statement endpoints stay single purpose

- **Decision**: `Feature/Report/` is read-only, with one operation: the report
  for a frequency and any date in the period, given the client's `today`. The
  server aligns the date to its period, so the client steps to the previous
  period with the day before the report's first day, and to the next with the
  day after its last. Without a date, the server picks the latest complete
  period, or the period to date when no complete one has data. The response also
  says whether earlier and later reports exist; any other period is `404`. The
  shared code is in `Domain/` (the balance sheet for a statement date, the
  income statement computation, savings rate, and reporting periods) and `Data/`
  (loading every line with its observations, and the income statement entries).
- **Why**: a report combines both statements, which no single statement endpoint
  should do, and the balance sheet endpoint stays the current sheet. Taking any
  date keeps period arithmetic on the server; the client only moves a day either
  side of the report it has. Slices do not import each other, so what the report
  and dashboard slices share lives in `Domain/`.
- **Goal**: the dashboard's history (dashboard decision 14) is the last twelve
  monthly reports and this month's report to date, computed by the same code.

### 8. One reports page shows one report at a time

- **Decision**: the reports page has a frequency picker (saved to localStorage,
  as a preference) and previous and next controls, disabled where no report
  exists. It opens on the latest complete period. It shows two sections. The
  balance sheet section has opening and closing net worth and working capital
  with their changes, other changes, and the closing balance sheet with its
  lines grouped by side. The income statement section has income, expenses, net
  income, savings rate, and the statement's lines. A report to date is marked as
  such.
- **Why**: one page and one read cover the goal questions for any period. A
  table of periods linking to a page per report was rejected: two pages and two
  reads to scan across periods, which the dashboard's history already does for
  months. The latest complete period is the default because a period to date is
  partial (dashboard decision 12), and the dashboard covers the current month.
- **Goal**: any period's position and performance in one place.

### 9. Each line has an observation history page

- **Decision**: each item and account has a page listing its observations,
  newest first, with a delete action each, confirmed with the app's delete
  dialog. The page header shows the line's name, side, term, current balance,
  and close date, with an action that records an observation using the line's
  value or balance form. Each line on the balance sheet has a "History" link to
  it. A line on the balance sheet opens that form, as an account's already did,
  and editing a line's details is reached from there. Deleting an account's last
  observation leaves its balance unknown. Deleting an item's last observation is
  rejected: an item always has a known value, so the user deletes the item
  instead.
- **Why**: with history in reports, a wrong old observation changes past figures
  while being invisible on today's sheet, so the user needs to see and remove
  it. A page rather than a modal: Kiwibank imports record an observation per
  transaction date, about 250 a year per account, and a page can page through
  them and has a route. Correcting an observation is recording one on the same
  date, so there is no edit action. This takes on "Observation history" from the
  CSV import brief's Deferred list.
- **Goal**: every balance that feeds a report can be found and corrected.

## Consequences

- **Schema.** Migration `001` is unreleased, so it changes in place: an item
  observations table, items without their balance and as-of date, and a close
  date on items and accounts. Run `just db-reset` and `just db-update`.
- **API.**
  - Item create takes an opening balance and as-of date and writes the first
    observation with the item. Item update no longer takes a balance.
  - Items and accounts each get operations to record, list, and delete
    observations, an observation identified by its line and as-of date.
  - `GET /api/balance-sheet` also returns closed lines, apart from the sheet
    (decision 4).
  - `Feature/Report/` has the report read.
- **Renames.** From the CSV import feedback, done with the item observations: an
  item's `Balance` becomes `Value`, so `Balance` means an account's signed
  balance only; and `ItemKind` becomes `Side`, used by items (fixed) and account
  lines (from the balance's sign). [Balance sheet](balance-sheet.md) changes to
  match.
- **Client.** Routes with an id, for the observation history pages; the reports
  page and a "Reports" link in the header; the closed lines section; and the
  item form without its value fields except on create.
- **Dashboard.** Its history uses monthly reports (dashboard decision 14).
- **Highest-value tests.** The balance sheet for a date (latest observation on
  or before it, lines entering at their first observation, closed lines, unknown
  accounts), reporting period arithmetic (aligning a date to its period,
  quarters, financial year boundaries, the first period, to date), report
  figures (other changes, the empty first opening sheet), the rule against
  deleting an item's last observation, and one E2E test each for the observation
  history and reports pages.

## Deferred

- **Paging.** The observation list returns everything. When paging is needed, it
  takes a `before` date and a limit, and the page appends with "Load more".
- **Comparative balance sheet.** A report shows the closing sheet only. Opening
  and closing balances side by side for each line, if the totals are not enough.
- **Comparing periods.** A table of a frequency's reports, or a report against
  the one before, if stepping between reports is not enough.
- **A line's balance chart.** On the observation history page, with the chart
  element planned for the dashboard.
- **Reconciliation.** Comparing an account's change in balance between
  observations with its transactions, as in the [CSV import](csv-import.md)
  Deferred list. The observation history page is where it would show.
- **Newly tracked lines.** A line first observed during a period adds its whole
  balance to that period's other changes, whether it is new or only newly
  entered. Recording an opening balance at an earlier date avoids it. Revisit if
  this proves confusing.

## Assumptions

- Single base currency, as in [balance-sheet.md](balance-sheet.md).
- The financial year starts on 1 April.
