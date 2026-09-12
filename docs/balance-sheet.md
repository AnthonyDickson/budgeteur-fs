# Balance sheet

Design brief for the assets and liabilities feature. It records what we decided, why, and what each decision is meant to
achieve, so later work (codec, slice, page) has one written source of intent. It is not a tutorial and it is not frozen;
change it when the reasoning changes.

## Goal

Let a user track what they own and what they owe, and read two numbers from it:

- **Net worth**: total assets minus total liabilities. The long-horizon position.
- **Working capital**: current assets minus current liabilities. The near-term position: whether near-term resources
  cover near-term obligations, and by how much. This is the short-term indicator, and it is the reason the feature
  exists. It supports budgeting and near-term decisions.

The page is a single, current snapshot valued as of the last update. Periodic snapshots (quarterly style, balance sheet
plus income statement) are a future goal, not this iteration.

## Ubiquitous language

| Term                | Meaning                                                                                                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BalanceSheet`      | The aggregate: every item, valued as of a single date.                                                                                                      |
| `BalanceSheetItem`  | One line: a single asset or a single liability.                                                                                                             |
| `ItemKind`          | `Asset` (owned) or `Liability` (owed). Gives a value its direction.                                                                                         |
| `Term`              | `Current` or `NonCurrent`, set by the user. For an asset, `Current` means liquid. For a liability, `Current` means short-term (due within about 12 months). |
| `Balance`           | The positive magnitude of an item's value, in the base currency, rounded to cents. Direction comes from `ItemKind`.                                         |
| Current assets      | Assets whose `Term` is `Current`.                                                                                                                           |
| Current liabilities | Liabilities whose `Term` is `Current`.                                                                                                                      |
| Net worth           | Total assets minus total liabilities.                                                                                                                       |
| Working capital     | Current assets minus current liabilities. The near-term position.                                                                                           |

The domain uses one axis, `Current` and `NonCurrent`, for both sides. Accounting calls assets "current or non-current";
planners call them "liquid or illiquid", and call liabilities "short-term or long-term". UI copy may use whichever word
reads best (`liquid`, `fixed`, `short-term`, `long-term`); the model always stores `Current` or `NonCurrent`.

## Decisions

### 1. The item is `BalanceSheetItem`, not `Account`

- **Decision**: the new concept is named for the balance sheet, not for an account.
- **Why**: `Account` already means a bank account in this codebase (`Transaction.AccountId`, the `Accounts` table). One
  word, two meanings, is a language bug that shows up later as confusion about which account a piece of code means.
- **Goal**: the ubiquitous language stays unambiguous, and this feature can evolve without dragging bank account
  semantics along. The existing `Accounts` table is out of scope for this iteration.

### 2. Two orthogonal axes: `ItemKind` and `Term`

- **Decision**: model asset-versus-liability and current-versus-non-current as two independent values, not one four-case
  union.
- **Why**: they are independent facts about an item. A single union of four cases conflates them and forces case
  matching to answer either question.
- **Goal**: aggregating by either dimension is a filter. "All assets", "all current items", and working capital fall out
  without enumerating cases, and a future dimension does not reshape existing ones.

### 3. `Balance` is a positive magnitude; `ItemKind` gives direction

- **Decision**: values are stored as non-negative magnitudes with the direction supplied by the classification. A
  negative magnitude is rejected.
- **Why**: it makes a value whose sign contradicts its classification unrepresentable. It also matches how the data will
  arrive: an overdrawn bank account is a current liability with a positive magnitude, not a negative asset.
- **Goal**: net worth is always assets minus liabilities, with no sign handling at the point of use, and invalid rows
  cannot be constructed. CSV import gets one rule: a negative balance becomes a `Liability`.

### 4. One snapshot, dated at last update, derived server-side

- **Decision**: the page shows a single current snapshot. `StatementDate` is set by the server and refreshed on every
  write to the sheet (item created, updated, or deleted). It is not user input, and it is not recomputed at read time,
  so it means "these balances are accurate as of the last update".
- **Why**: the roadmap calls for a current view, and users should not have to pick a valuation date. Storing the date
  and bumping it on writes makes accuracy a property of the data rather than a function of when the page happened to
  load. Keeping `StatementDate` on the aggregate is also the seam periodic reporting will need.
- **Goal**: the simplest correct model today, with a date that is honest about when the snapshot was last taken, and a
  place for dated snapshots to slot in later without reshaping items (items carry no date; the sheet does).
- **Name**: the field is `StatementDate`, the standard term for the date a financial statement is drawn as of. It is a
  noun phrase rather than the idiomatic but grammatically odd `AsOf`, and it does not overload `Current`, which in this
  context already means the near-term `Term`.

### 5. Standalone from `Accounts` and transactions for now

- **Decision**: do not link balance sheet items to the existing accounts or transactions yet. Keep the item model
  generic.
- **Why**: linkage and CSV-driven balance updates are not designed. Coupling now would constrain two features that
  currently have nothing to say to each other.
- **Goal**: a general model that can later accept imported balances. The intended mapping when that arrives is by
  classification: savings to a current asset, credit card and overdraft to a current liability.

### 6. Totals are computed server-side

- **Decision**: totals and net worth come from the API; the client renders them and never sums.
- **Why**: `client/src/budgeteur/shared/money.gleam` documents the rule that the frontend only displays money and never
  aggregates it, because JavaScript floats drift. All money math uses the backend `decimal`.
- **Goal**: one source of truth for money arithmetic. The read response carries the computed figures.

### 7. `Term` follows the practitioner liquid test

- **Decision**: the user sets `Term`; it is not derived. For an asset, `Current` means it is cash or can be converted to
  cash quickly without significant loss of principal (liquid). For a liability, `Current` means it is due to be settled
  in the near term, conventionally within about 12 months (short-term). Everything else is `NonCurrent`.
- **Why**: this is how financial planners build personal balance sheets, which are single-entry and not GAAP. They split
  assets into liquid, investment, and use assets, and liabilities into short-term and long-term. The accounting
  standards (IAS 1.66 and 1.69, ASC 210-10-45) instead apply an expectation-within-12-months test designed for
  businesses, which misclassifies a breakable long deposit and treats a car as a fixed asset rather than a liquid one.
- **Goal**: a rule the user can apply sensibly to personal items, where `Current` means liquid for assets, so working
  capital is meaningful.
- **Basis**: IAS 1 paragraphs 66 and 69; ASC 210-10-45; planner sources: NerdWallet, Financial Planning Authority, and
  the State Farm/Advisys net worth worksheet.

### 8. The near-term indicator is working capital

- **Decision**: the short-term figure is working capital, current assets minus current liabilities. We do not show the
  common "liquid net worth" (liquid assets minus all liabilities).
- **Why**: the all-liabilities form is dominated by long-term debt, so near-term changes in savings or credit card debt
  barely move it, and it measures solvency rather than budgeting. Working capital isolates near-term coverage and stays
  sensitive to the decisions a tight budget turns on.
- **Goal**: a number that shows whether spending pushes near-term obligations above near-term resources.
- **Note**: this is a stock measure. Affordability in cash-flow terms also needs income, which is out of scope until the
  income statement exists.

## Consequences

- **Domain gap closed.** The domain computes the current-only totals and working capital
  (`BalanceSheet.totalCurrentAssets`, `totalCurrentLiabilities`, `workingCapital`), pinned by tests.
- **Read DTO.** The response carries `StatementDate` plus the computed totals (total assets, total liabilities, net
  worth, current assets, current liabilities, working capital) and the items. The client derives nothing.
- **Item shape.** `Id`, `Name`, `Kind`, `Term`, `Balance`. No date, no account reference, no currency.
- **Classification edges.** Under the liquid test a car is `NonCurrent` (a use asset), and a 3-year term deposit is
  `NonCurrent` unless it is genuinely liquid. The two-value axis collapses the planner three-bucket asset split (liquid,
  investment, use); that is enough for working capital.

## Deferred

- Snapshot history and periodic reports (the reason `StatementDate` exists on the aggregate).
- Income and cash flow (the income statement), so affordability can be judged in flow terms rather than only as a stock
  position.
- Linkage to `Accounts` and balance updates from CSV import.
- Multi-currency. A single base currency is assumed, because the app is intended to stay local and self-hosted with no
  FX plans.

## Assumptions

- Single base currency. No per-item currency field, no FX.
- Working capital counts `Current` items on both sides and nothing else: current assets minus current liabilities.
