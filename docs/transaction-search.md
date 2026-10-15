# Transaction search

Design brief for transaction search: narrowing the transactions page by
description, date, account, tag, and amount. It records what we decided, why,
and what each decision is meant to achieve. Change it when the reasoning
changes.

Before this feature the transactions page fetched every transaction in one
request and sorted them on the client. The previous Rust project (`budgeteur`,
`docs/transaction-table-design-spec.md`) paged by date range and had no search;
its roadmap listed search and filtering as a follow-up.

## Goal

- **Find one transaction.** A few keystrokes find a specific transaction to
  check or edit, however old it is.
- **See the transactions behind a number.** The user sees every transaction for
  a merchant, tag, account, or period, such as those behind a line in a report.
- **The page stays fast as history grows.** The page loads one page of
  transactions, not all of them, and the server does no work it throws away.

## Ubiquitous language

| Term          | Meaning                                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------- |
| Search        | The criteria the user has set. With no criteria set, the search matches every transaction.                          |
| Criterion     | One condition of a search: text, dates, account, tag, or amount. A search matches transactions meeting all of them. |
| Match         | A transaction that meets every criterion of the search.                                                             |
| Date preset   | A named date range resolved by the server from the client's `today`, e.g. last month.                               |
| Page          | Up to 100 matches, newest first, starting after a cursor.                                                           |
| Cursor        | An opaque value marking where the next page starts. No cursor on the last page.                                     |
| Credit, debit | A transaction with a positive amount, and one with a negative amount, as in the transaction form.                   |

Categorisation, untagged, dismissed, transfer, and without a tag are defined in
[auto-tagging](auto-tagging.md#ubiquitous-language) and
[quick tagging](quick-tagging.md#ubiquitous-language).

## Decisions

### 1. Search narrows the transactions page

- **Decision**: search is part of the transactions page, not a page of its own.
  The page always shows the results of the current search. With no criteria set,
  the results are every transaction, so the page's first load is a search. A
  search combines its criteria with AND:
  - text in the description (decision 2),
  - a date range, from a preset or custom dates (decision 3),
  - an account, or no account (decision 4),
  - a tag or a categorisation state (decision 4),
  - a direction and a range of amount sizes (decision 5).
- **Why**: both goals end on the transactions page: editing happens there, and
  the rows are the evidence behind a report's numbers. A separate page would
  duplicate the table, the transaction form, and its edit flow.
- **Rejected**: multiple values per criterion (several tags or accounts). It
  needs a custom multi-select control and list-valued criteria. Reports and the
  dashboard already break spending down by tag.
- **Goal**: one table of transactions, which a search narrows.

### 2. Text matches like rules

- **Decision**: the text criterion matches when it occurs anywhere in the
  description under the rule comparison: ordinal, ignoring case
  ([auto-tagging](auto-tagging.md) decision 1). It is trimmed and validated like
  a rule pattern, except that blank text sets no criterion. No wildcards, word
  splitting, or accent folding.
- **Implementation**: SQLite runs the match. The search query registers a .NET
  function on its connection that compares with the rule comparison, and calls
  it from the query's `where` clause. The function lives in `Data/`, so other
  queries can use it.
- **Why**: a search for some text then previews exactly what a rule with that
  pattern would match, so a search can become a rule (see Deferred). Matching in
  SQL keeps paging in SQL (decision 6), so the server reads only the rows it
  returns.
- **Cost**: substring matching cannot use an index, so each search scans the
  user's transactions in the date range. A .NET call per row is slower than a
  built-in function, which does not matter at personal scale.
- **Rejected**:
  - SQLite `LIKE`. It folds ASCII case only, so `ōtaki` would not find `ŌTAKI`
    though a rule would match it. `%` and `_` in the text act as wildcards, and
    the query library's `LIKE` cannot add an `ESCAPE` clause.
  - A folded copy of the description stored beside it, searched with `instr`.
    Exact, but a second copy of a fact that every write path must keep in step.
  - SQLite full-text search (FTS5). It adds a virtual table to keep in sync, and
    its tokenised matching differs from rules.
  - Matching every word in any order. More forgiving, but it no longer previews
    a rule.
  - Filtering in F# after reading rows. It reads every row in range to return
    100, and leaves paging in F#.
- **Goal**: search and rules agree on what text matches.

### 3. Date presets are resolved by the server

- **Decision**: the dates criterion is one of: any time, this month, last month,
  this year, last year, this financial year, last financial year, or custom.
  Months and years are calendar months and years. Financial years start on 1
  April, as in [reports](reports.md) decision 5. A preset is sent with the
  client's `today`; the server resolves it with the reporting periods in
  `Domain/`, and the response carries the resolved first and last days, which
  the page shows beside the select. "Last" is the period containing the day
  before the current period's first day. Custom has optional first and last
  days, both inclusive; a first day after the last day is `400`.
- **Why**: period arithmetic already lives on the server for reports, with the
  financial year's start in one place. The client supplies `today` because the
  server has no timezone ([dates](dates.md)).
- **Rejected**:
  - The client computing presets into dates. Simpler requests, but the financial
    year's start would be duplicated in Gleam.
  - Rolling windows (last 30 or 90 days). Spending is reviewed by calendar
    period in reports and the dashboard.
- **Goal**: the periods the user already thinks in, one select away, with the
  same boundaries as reports.

### 4. Account and tag are single selects

- **Decision**:
  - **Account**: any, no account, or one of the user's accounts.
  - **Tag**: any, without a tag (untagged or dismissed), untagged, dismissed,
    transfer, or one of the user's tags, grouped into expense and income tags,
    each by name.

  Both are native selects. The request carries each as a state and an optional
  id, validated together: an id with a state that takes none, or a missing id,
  is `400`. An id the user does not have matches nothing, because every query is
  scoped to the user; search writes nothing, so there is no existence check.
- **Why**: native selects work with Vimium and on phones with no custom
  controls. The categorisation states are the ones the user already acts on in
  quick tagging. The request avoids a union with fields, which the OpenAPI
  document cannot describe ([openapi](openapi.md)).
- **Rejected**: filtering by tag source (manual or rule). Auditing rules is not
  a goal of this feature.
- **Goal**: every way a transaction is categorised can be searched for.

### 5. Amounts filter by direction and size

- **Decision**: the amount criterion is a direction (any, credit, debit) and an
  optional minimum and maximum size: the absolute amount, inclusive. A credit is
  a positive amount and a debit a negative one, so a zero amount matches only
  with any direction. Sizes are money: non-negative, at most two decimal places,
  and a minimum above the maximum is `400`.
- **Why**: "a debit of 50 to 200" is how a user describes an expense they are
  looking for. Signed bounds make expenses read backwards (−200 to −50).
- **Rejected**:
  - Signed minimum and maximum.
  - An exact amount only. A range with equal bounds covers it.
- **Goal**: a transaction can be found by roughly how much it was.

### 6. Results page by keyset; "Load more" appends

- **Decision**: matches are ordered by date, newest first, then by id, newest
  first, as in the quick tagging queue. A page is 100 matches. The response
  carries a cursor for the next page, or none on the last page. The page shows a
  "Load more" button while there is a cursor, which fetches the next page with
  the same criteria and appends it, skipping rows already shown (decision 10). A
  changed search replaces the results. The cursor is opaque to the client and
  encodes the date and id of the page's last transaction; a malformed cursor is
  `400`.
- **Why**: one page answers most searches, and TODO.md expected paging to be
  rare. Keyset paging stays correct when transactions are added or deleted
  between pages, which offsets do not. Ordering by id breaks ties
  deterministically, which a cursor needs; the previous tie-break by description
  was a client-side sort.
- **Cost**: the order of transactions on the same day changes from by
  description to by creation (ids are v7 UUIDs).
- **Rejected**:
  - Offset paging. Rows shift or repeat when transactions change between pages.
  - Infinite scroll. It needs an intersection observer through FFI, and Vimium
    cannot target it.
  - A next-page path in the response. The request is a POST body (decision 7),
    so the client resends its criteria with the cursor.
- **Goal**: the page loads one page of transactions, however long the history.

### 7. Search is a POST to the Transaction slice

- **Decision**: `POST /api/transactions/search` in `Feature/Transaction/` takes
  the criteria, the client's `today`, and an optional cursor as a JSON body. It
  returns the page of transactions, in the shape the slice already returns, the
  next cursor, and the resolved first and last days. Invalid criteria are `400`.
  The slice's pure search module validates the criteria and resolves presets;
  the query applies them. `GET /api/transactions` stays, for manual testing and
  inspection, and is registered in development only, like the balance sheet item
  list.
- **Why**: the criteria have structure (a state with an optional id, a direction
  with bounds, a preset or custom dates). A body gives one request type, decoded
  and described in the OpenAPI document from the type, where nine query
  parameters would each be parsed and documented by hand. Money stays a JSON
  string, as in every other request. Search text and amounts stay out of URLs
  and so out of proxy access logs. Search is the slice's read, so it stays in
  the slice.
- **Cost**: a read over POST. HTTP defines POST as neither safe nor idempotent
  (RFC 9110, sections 9.2.1 and 9.2.2), so clients do not retry it after a
  connection failure, and caches do not store its responses in practice. The
  page neither caches nor retries searches, so neither matters here; the method
  just does not say the request is a read.
- **Rejected**:
  - `GET` with query parameters. Usable from the address bar, but parsed and
    documented by hand, and the search text ends up in proxy logs.
  - The `QUERY` method (RFC 10008), a safe and idempotent request with a body,
    made for this case. The Oxpecker release in use cannot route it; its
    development branch can. Revisit when a release supports it.
  - Removing `GET /api/transactions`. It is useful for inspecting data in
    development.
- **Goal**: one typed read serves the page, and the full list stays available
  where it is useful.

### 8. The search lives in the page model only

- **Decision**: the criteria are page state. They are not in the URL or in
  localStorage, and leaving the page clears them.
- **Why**: the simplest routing, with no query parameters to parse. Search text
  and amounts are financial data, which the client does not persist
  ([architecture](architecture.md#requirements-and-constraints)); a URL would
  keep them in browser history.
- **Cost**: reloading clears the search, and other pages cannot link to a
  search, such as a tag's transactions for a month.
- **Goal**: no routing changes.

### 9. Searches run as the user types

- **Decision**: the text criterion runs a search once typing pauses, with the
  same delay as the rule modal's match count. Other controls run a search when
  they change. A response for criteria other than the current ones is ignored,
  so a slow response never replaces a newer one. While a search is in flight,
  the previous results stay, with a "Searching…" note above the table. Invalid
  input (a custom first day after the last day, a malformed size, a minimum
  above the maximum) shows an error on the field and runs no search.
- **Errors**: a failed first load shows the page's error state with a retry, as
  now. A later failed search, or a failed "Load more", shows the error toast and
  keeps the results shown.
- **Why**: as-you-type matches the rule modal and makes finding a transaction a
  matter of a few keystrokes. Keeping the previous results avoids the table
  flashing on every pause in typing.
- **Goal**: results follow the criteria without a submit step or flicker.

### 10. Changes apply to the rows shown

- **Decision**: the results are the last search's matches plus the user's own
  changes. A change never runs the search again; changing the criteria does.
  - **Update**: the row is replaced in place and keeps its position, even if its
    date changed or it no longer matches, until the next search.
  - **Create**: the transaction is added at the top of the results, whatever its
    date and the criteria.
  - **Delete**: the row is removed.
  - **Import**: the search runs again from the first page.

  "Load more" skips transactions already shown, so a created or edited row that
  also falls on a later page is not listed twice. The success toasts are
  unchanged.
- **Why**: after an edit, the user wants to see the result. A row that vanishes
  because it no longer matches looks like a lost edit, and reloading the list on
  save ties editing to searching. Rows that stay in place follow
  [quick tagging](quick-tagging.md) decision 4. The client cannot decide whether
  a row matches, because text matching uses the server's comparison. An import
  adds rows the user has not seen, which cannot be patched in, and its toast
  marks the reload.
- **Cost**: until the next search, the results can hold rows that no longer
  match, and a created row out of date order.
- **Rejected**: running the search again after every change. The results stay
  exact, but an edited row can disappear, and pages added with "Load more" are
  dropped.
- **Goal**: the user sees the effect of every change they make, and the list
  changes only when they search or import.

### 11. UI

- **Layout**: below the page header, a search box ("Search descriptions"), a
  "Filters" button showing how many criteria other than text are set, and a
  "Clear" button, shown while any criterion is set, that resets all of them. The
  "Filters" button opens and closes a panel holding the dates select (with the
  first and last day inputs when custom, and the resolved range for a preset),
  the account and tag selects, and the direction select with the minimum and
  maximum sizes. The panel's fields stack on narrow screens.
- **Table**: unchanged columns. "Load more" below it while there is a next page.
- **Empty states**: with no criteria set and no results, the existing "No
  transactions yet". With criteria set and no results, "No transactions match
  your search" with a "Clear search" button.
- **Selectors**: every new control has a `data-testid`.
- **Goal**: the search box is always one click away, and the rest of the
  criteria take no space until needed, which matters with mobile support next on
  the roadmap.

## Consequences

- **Transaction slice**: gains the search endpoint, its request and response
  types, and a pure search module. The list endpoint moves to the slice's
  development-only endpoints; the test host registers them as it does for the
  balance sheet.
- **`Data/`**: gains the description-matching SQL function.
- **Client**: the page fetches through search, keeps the criteria, the results,
  and the cursor, and no longer sorts transactions. Updates and deletes patch
  the rows, creates are added at the top, and imports run the search again.
- **Highest-value tests**:
  - Matching function: ignores case for ASCII and non-ASCII letters, and treats
    `%` and `_` as plain characters.
  - Search module: criteria validation (`400` cases), preset resolution
    including financial years and January's "last month", cursor round-trip.
  - Search endpoint: each criterion, criteria combined, only the caller's
    transactions, page size and cursor across pages with same-day ties.
  - Client: a search replaces results and "Load more" appends; a response for
    old criteria is ignored; an update patches the row in place even when it no
    longer matches; a create is added at the top; "Load more" skips rows already
    shown; an import runs the search again; invalid input sends nothing; a
    failed search keeps the results and shows a toast.
  - E2E: create transactions, search by text, narrow by tag, check the rows,
    edit a match so it no longer matches and check it stays listed, then clear
    the search.

## Deferred

- **Totals for a search.** The match count, and the credits, debits, and net of
  the matches that are not transfers, from a summary endpoint beside search,
  fetched again after each change. Settled so far: credits and debits, not
  income and expenses, because the income statement nets refunds per tag
  ([dashboard](dashboard.md) decision 3); transfers left out, because a search
  across accounts would count each twice. Exact sums in SQL need money stored as
  integer cents first, because `CURRENCY` columns hold doubles
  ([database](database.md#money-columns)). Left out of this feature because the
  summary, keeping it current after changes, and the storage change cost more
  than the goals needed.
- **Links to a search.** From the dashboard or reports to, e.g., a tag's
  transactions for a month. Needs the search in the URL (decision 8).
- **Create a rule from a search.** The text criterion already matches like a
  rule; see [auto-tagging](auto-tagging.md#deferred).
- **Multiple values per criterion.** Several tags or accounts (decision 1).
- **Accent-insensitive matching.** `otaki` does not find `ŌTAKI`. Rules would
  need the same change to stay in agreement.
- **Sortable columns.** Newest first serves both goals; keyset paging would need
  a cursor per order.
- **The rule match count in SQL.** It can use the matching function instead of
  reading every description.
- **Searching other fields.** Account or tag names as text, or amounts typed
  into the search box.

## Assumptions

- A user has at most tens of thousands of transactions, so scanning one user's
  transactions per search is fast enough.
- A user has few enough tags and accounts that a native select lists them
  comfortably.
- Searches are short-lived: the user does not need a search to survive a reload.
