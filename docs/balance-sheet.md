# Balance sheet

Design brief for the assets and liabilities feature. It records what we decided,
why, and what each decision is meant to achieve, so later changes have one
written source of intent. It is not a tutorial and it is not frozen; change it
when the reasoning changes.

## Goal

Let a user track what they own and what they owe, and read two numbers from it:

- **Net worth**: total assets minus total liabilities. The long-horizon
  position.
- **Working capital**: current assets minus current liabilities. The near-term
  position: whether near-term resources cover near-term obligations, and by how
  much. This is the short-term indicator, and it is the reason the feature
  exists. It supports budgeting and near-term decisions.

The page shows the sheet as of today, with each line dated by when its balance
was last set. Periodic snapshots (quarterly style, balance sheet plus income
statement) are a future goal, not this iteration.

## Ubiquitous language

| Term                | Meaning                                                                                                                                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BalanceSheet`      | The aggregate: every item and account, drawn for one date, the statement date.                                                                                                                            |
| Statement date      | The date the sheet is drawn for, in the financial-statement sense. Today on the current page; the requested date for a snapshot. Not stored. Unrelated to the bank statements CSV import reads.           |
| As-of date          | The date a line's balance is accurate as of. Every line has one.                                                                                                                                          |
| `BalanceSheetItem`  | One line: a single asset or a single liability that is not an account.                                                                                                                                    |
| Account             | Somewhere the user's transactions happen. Also a line, with a signed balance; see [CSV import](csv-import.md).                                                                                            |
| `ItemKind`          | `Asset` (owned) or `Liability` (owed). Gives a value its direction.                                                                                                                                       |
| `Term`              | `Current` or `NonCurrent`, set by the user. For an asset, `Current` means liquid. For a liability, `Current` means short-term (due within about 12 months).                                               |
| `Balance`           | An item's balance: the positive magnitude of its value, in the base currency, rounded to cents. Direction comes from `ItemKind`. An account's balance is signed instead; see [CSV import](csv-import.md). |
| Current assets      | Assets whose `Term` is `Current`.                                                                                                                                                                         |
| Current liabilities | Liabilities whose `Term` is `Current`.                                                                                                                                                                    |
| Net worth           | Total assets minus total liabilities.                                                                                                                                                                     |
| Working capital     | Current assets minus current liabilities. The near-term position.                                                                                                                                         |

The domain uses one axis, `Current` and `NonCurrent`, for both sides. Accounting
calls assets "current or non-current"; planners call them "liquid or illiquid",
and call liabilities "short-term or long-term". UI copy may use whichever word
reads best (`liquid`, `fixed`, `short-term`, `long-term`); the model always
stores `Current` or `NonCurrent`.

## Decisions

### 1. The item is `BalanceSheetItem`, not `Account`

- **Decision**: the new concept is named for the balance sheet, not for an
  account.
- **Why**: `Account` means somewhere the user's transactions happen
  (`Transaction.AccountId`, the `Accounts` table). One word, two meanings, is a
  language bug that shows up later as confusion about which account a piece of
  code means.
- **Goal**: the ubiquitous language stays unambiguous. An item is a holding that
  is not an account; accounts are a separate source of lines (decision 5).

### 2. Two orthogonal axes: `ItemKind` and `Term`

- **Decision**: model asset-versus-liability and current-versus-non-current as
  two independent values, not one four-case union.
- **Why**: they are independent facts about an item. A single union of four
  cases conflates them and forces case matching to answer either question.
- **Goal**: aggregating by either dimension is a filter. "All assets", "all
  current items", and working capital fall out without enumerating cases, and a
  future dimension does not reshape existing ones.

### 3. `Balance` is a positive magnitude; `ItemKind` gives direction

- **Decision**: values are stored as non-negative magnitudes with the direction
  supplied by the classification. A negative magnitude is rejected.
- **Why**: it makes a value whose sign contradicts its classification
  unrepresentable. It also matches how the data will arrive: an overdrawn bank
  account is a current liability with a positive magnitude, not a negative
  asset.
- **Goal**: net worth is always assets minus liabilities, with no sign handling
  at the point of use, and invalid rows cannot be constructed.
- **Accounts**: this decision applies to items. An account's balance is signed,
  because an overdraft changes its side; the read model turns it into a line
  with a magnitude, and a negative balance becomes a `Liability` (decision 5).

### 4. Each line is dated; the sheet is drawn for a date

- **Decision**: every line carries its as-of date. An item's is set with its
  balance and defaults to the client's today; an account's is its current
  balance's ([CSV import](csv-import.md) decision 3). An as-of date later than
  the server's UTC date plus one day is rejected, as for account balances. The
  sheet stores no date of its own: its statement date is the date it is drawn
  for, which on the current page is the client's today ([dates](dates.md)),
  shown in the header. Each line shows its as-of date, so a stale balance is
  visible.
- **Why**: a stored sheet date has to be refreshed by every write that changes a
  line, which spreads one rule across the balance sheet, account, and import
  slices, and one date cannot say that lines were valued on different days.
  Dating each line keeps the date with the balance it describes. A snapshot
  (Deferred) is the same read for an earlier date, so the current page and
  snapshots get their date the same way. The default means entering a balance
  needs no date unless it is an old one.
- **Rejected**:
  - A `StatementDate` stored on the sheet and refreshed on every write to an
    item or account, the previous design. See Why.
  - The latest as-of date among the lines as the statement date. It hides a
    stale line behind a fresh one, and for a snapshot it would show the newest
    line's date instead of the date asked for.
- **Goal**: the sheet's date is derived one way for the current page and for
  snapshots, and how current each line is stays visible.
- **Name**: statement date is the standard term for the date a financial
  statement is drawn as of; as-of date matches the account balance term in
  [CSV import](csv-import.md). Neither overloads `Current`, which in this
  context already means the near-term `Term`.

### 5. Accounts are a second source of lines

- **Decision**: items stay unlinked from accounts and transactions. The read
  model combines items with the user's accounts: an account with a known balance
  is a line in its `Term` group, an `Asset` when the balance is zero or more and
  a `Liability` when it is negative, with the balance's magnitude. Accounts with
  an unknown balance are left out of totals and listed separately. Totals, net
  worth, and working capital include both sources.
- **Why**: an account's side follows its balance, which a fixed `ItemKind`
  cannot. Combining at read time keeps the item invariants and stores each
  balance once. The account model and the rejected alternatives are in
  [CSV import](csv-import.md) decisions 1 to 3.
- **Goal**: imported and manually entered account balances count towards net
  worth and working capital without changing what an item is.

### 6. Totals are computed server-side

- **Decision**: totals and net worth come from the API; the client renders them
  and never sums.
- **Why**: the client only displays money and never aggregates it, because
  JavaScript numbers are doubles. All money arithmetic uses the backend
  `decimal` ([architecture](architecture.md#money)).
- **Goal**: one source of truth for money arithmetic. The read response carries
  the computed figures.

### 7. `Term` follows the practitioner liquid test

- **Decision**: the user sets `Term`; it is not derived. For an asset, `Current`
  means it is cash or can be converted to cash quickly without significant loss
  of principal (liquid). For a liability, `Current` means it is due to be
  settled in the near term, conventionally within about 12 months (short-term).
  Everything else is `NonCurrent`.
- **Why**: this is how financial planners build personal balance sheets, which
  are single-entry and not GAAP. They split assets into liquid, investment, and
  use assets, and liabilities into short-term and long-term. The accounting
  standards (IAS 1.66 and 1.69, ASC 210-10-45) instead apply an
  expectation-within-12-months test designed for businesses, which misclassifies
  a breakable long deposit and treats a car as a fixed asset rather than a
  liquid one.
- **Goal**: a rule the user can apply sensibly to personal items, where
  `Current` means liquid for assets, so working capital is meaningful.
- **Basis**: IAS 1 paragraphs 66 and 69; ASC 210-10-45; planner sources:
  NerdWallet, Financial Planning Authority, and the State Farm/Advisys net worth
  worksheet.

### 8. The near-term indicator is working capital

- **Decision**: the short-term figure is working capital, current assets minus
  current liabilities. We do not show the common "liquid net worth" (liquid
  assets minus all liabilities).
- **Why**: the all-liabilities form is dominated by long-term debt, so near-term
  changes in savings or credit card debt barely move it, and it measures
  solvency rather than budgeting. Working capital isolates near-term coverage
  and stays sensitive to the decisions a tight budget turns on.
- **Goal**: a number that shows whether spending pushes near-term obligations
  above near-term resources.
- **Note**: this is a stock measure. Affordability in cash-flow terms also needs
  income, which is out of scope until the income statement exists.

### 9. The on-screen label is "Working capital"

- **Decision**: the summary card and any copy that names the figure use "Working
  capital". The model field is `workingCapital`.
- **Why**: it is the domain term from decision 8. "Short-term net worth"
  overstates what the figure covers, and "Net cash" reads as cash only, hides
  that near-term liabilities are subtracted, collides with the app's bank
  accounts, and clashes with the cash-flow sense of "net cash flow". "Net
  current assets" and "Near-term position" were dropped as less familiar to the
  target user.
- **Goal**: the label matches the term the practitioner sources use, so the page
  and the design brief agree.

## Consequences

- **Read DTO.** The response carries the computed totals (total assets, total
  liabilities, net worth, current and non-current subtotals for each side,
  working capital), the items and account lines with their as-of dates, and the
  accounts with an unknown balance. It has no statement date: the client shows
  its today. The client computes no figures.
- **No sheet row.** A sheet is the user's items and accounts, with nothing
  stored for the sheet itself, so a user with neither gets an empty sheet, not
  `404`. The client shows it as an empty state.
- **Item shape.** `Id`, `Name`, `Kind`, `Term`, `Balance`, `AsOf`. No account
  reference, no currency.
- **Kind is fixed at creation.** For items. The page creates assets and
  liabilities from separate entry points, so `Kind` is never a field in the form
  and a value cannot silently end up on the wrong side of the sheet. Moving an
  item to the other side means deleting it and recreating it, which keeps `Kind`
  immutable like the rest of the model.
- **Classification edges.** Under the liquid test a car is `NonCurrent` (a use
  asset), and a 3-year term deposit is `NonCurrent` unless it is genuinely
  liquid. The two-value axis collapses the planner three-bucket asset split
  (liquid, investment, use); that is enough for working capital.

## Deferred

- Snapshot history and periodic reports: the read takes the statement date
  instead of using today (decision 4). Account balances are kept as dated
  observations from the CSV import onward; the intended approach, items getting
  observations too (their balance and as-of date becoming the first) and
  snapshots queried for a date, is under Deferred in
  [CSV import](csv-import.md).
- Income and cash flow (the income statement), so affordability can be judged in
  flow terms rather than only as a stock position.
- Multi-currency. A single base currency is assumed, because the app is intended
  to stay local and self-hosted with no FX plans.

## Assumptions

- Single base currency. No per-item currency field, no FX.
- Working capital counts `Current` items on both sides and nothing else: current
  assets minus current liabilities.
