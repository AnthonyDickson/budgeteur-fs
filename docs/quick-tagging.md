# Quick tagging

Design brief for quick tagging: tagging, one click per transaction, the
transactions that rules did not tag. It records what we decided, why, and what
each decision is meant to achieve. Change it when the reasoning changes.

The previous Rust project (`budgeteur`, `server/src/transaction/quick_tagging/`
and `docs/untagged-transactions-tech-spec.md`) kept a queue table filled by CSV
imports with the transactions no rule tagged, emptied by a trigger when a tag
was set. The page showed 20 cards, each with a radio button per tag and a
dismiss checkbox, and saved them together with an "Apply changes" button.
Dismissing deleted the queue row and left the transaction untagged. Lessons from
it are cited where they shaped a decision.

## Goal

- **One click to tag.** Choosing a tag for a transaction is a single click that
  saves it. No apply step, and no work lost if the user stops halfway.
- **Keyboard driven through Vimium.** Every tag choice is a control that
  Vimium's link hints find and click.
- **An empty queue means done.** Transactions the user dismisses leave the queue
  and stay out of it, and rules never tag them.

## Ubiquitous language

| Term          | Meaning                                                                                                       |
| ------------- | ------------------------------------------------------------------------------------------------------------- |
| Untagged      | A transaction with no assignment: nobody has tagged or dismissed it. It is waiting for a tag.                 |
| Dismissed     | A transaction the user decided has no tag. A manual decision, stored as an assignment; rules never change it. |
| Without a tag | Untagged or dismissed. The income statement's untagged lines cover both.                                      |
| Queue         | The user's untagged non-transfer transactions, newest first.                                                  |
| Batch         | The first 50 transactions of the queue, as fetched by the quick tagging page.                                 |
| Quick tag     | Choosing a tag for a queued transaction, or dismissing it. Either is a manual decision.                       |

Assignment, tag source, manual tag, and rule tag are defined in
[auto-tagging](auto-tagging.md#ubiquitous-language).

## Decisions

### 1. Dismissed is an assignment state

- **Decision**: an assignment is either a tag with its source (`Manual` or
  `Rule`), or a dismissal, which is always manual. A rule never dismisses, and
  the domain type cannot express a rule dismissal. Quick tagging's "Dismiss"
  button records it.
- **Storage**: the assignment's tag becomes nullable; a row without a tag is a
  dismissal. A check requires the `Manual` source on a row without a tag. One
  row per transaction still holds, so a transaction cannot be tagged and
  dismissed at once. The codec in `Data/` maps the nullable tag to the dismissed
  case, so the null does not leave `Data/`. Deleting a tag still deletes its
  assignments, so its transactions become untagged and return to the queue;
  dismissals reference no tag and are unaffected. Migration `001` is unreleased
  (no version tag contains it), so it is edited in place.
- **Transitions** (additions to [auto-tagging](auto-tagging.md) decision 4):
  - Quick tagging with a tag makes it manual; dismissing makes it dismissed.
    Either replaces whatever assignment the transaction had.
  - Creating a transaction without a tag leaves it untagged, so it appears in
    the queue. A tag the user forgot is what the queue is for, and dismissing is
    one click there.
  - The transaction form: choosing a tag for a dismissed transaction makes it
    manual, and saving one with no tag keeps it dismissed. Clearing the tag of a
    tagged transaction makes it untagged, as before, so it returns to the queue:
    a transaction whose tag was just cleared probably needs another.
  - Tag untagged and re-tag treat a dismissal as a manual decision and never
    change it.
  - A transfer has no assignment, dismissals included: marking a transaction as
    a transfer removes its assignment, and unmarking one makes it untagged.
- **Why**: the queue needs to know which untagged transactions the user has
  already decided on, and rules need the same fact to avoid tagging them. One
  row per transaction answers both, so they cannot disagree, and replacing a
  dismissal with a tag is the existing upsert.
- **Cost**: an assignment no longer always has a tag. Readers that take the tag
  straight from a join see a dismissal as untagged, with no compiler warning;
  readers that need the difference check whether the row exists.
- **Rejected**:
  - A dismissals table beside the assignments. No nullable column, and the
    assignment keeps meaning "a transaction's tag", but the schema allows a
    transaction to be both tagged and dismissed. The assignment store, or two
    triggers, would have to prevent it, and readers that forget the second table
    silently treat dismissed transactions as untagged, auto-tagging included.
  - A "No tag" tag per user. Every reader of tags (the tag list, rule tag
    select, tag kind, colour, income statement) would special-case it.
  - A dismissed flag on `Transactions`. It puts categorisation back on the
    transaction, against auto-tagging decision 3.
  - Clearing a tag in the transaction form dismisses the transaction. It would
    resolve the known limitation in auto-tagging decision 4, but a cleared tag
    usually means the tag was wrong, not that the transaction has none.
- **Goal**: every manual decision about a transaction's tag, including "none",
  is recorded once and respected by every writer.

### 2. The queue is a query over assignments

- **Decision**: the queue is every untagged non-transfer transaction of the
  user, whether imported or entered by hand, ordered by date, newest first, then
  by id, newest first. There is no queue table. A batch is the first 50 with the
  total in the queue. Fetching again returns the next batch, because tagged and
  dismissed transactions no longer match.
- **Why**: untagged already means "no assignment" (auto-tagging decision 3), so
  a table would be a second record of the same fact. Newest first puts a recent
  import's leftovers and the current period at the top. Without offsets, nothing
  has to track which transactions the user has seen.
- **Cost**: a transaction the user skips, neither tagging nor dismissing it,
  comes back at the top of the next batch. Dismissing is the way to clear it.
- **Rejected**:
  - Imported transactions only, as in the previous project. A transaction
    entered without a tag would never be reviewed, though the income statement
    still counts it in the untagged lines.
  - Offset or cursor paging. Not needed when the query shrinks as the user
    works.
- **Goal**: the queue is exactly the transactions that need a decision, with no
  state to keep in sync.

### 3. One click saves one transaction's tag

- **Decision**: each tag choice or dismissal sends its own request, which writes
  a manual assignment for one transaction. There is no batch submit.
- **Why**: the goal is one click per transaction. The previous project's apply
  step held a page of choices in unsaved form state, and lost them if the user
  navigated away. [CSV import](csv-import.md) decision 11 already settled on
  saving each tag as it is chosen.
- **Cost**: one request per transaction. For a personal app on SQLite this is
  negligible.
- **Goal**: every click is saved work.

### 4. Rows stay in place after tagging

- **Decision**: a quick tagged row stays where it is, with the chosen button
  marked as pressed and the row muted. Clicking another choice in the row
  changes it, again in one click. A row's buttons are disabled while its request
  is in flight; on failure the row returns to its previous state and the error
  toast is shown. "Next batch" at the bottom fetches the queue again.
- **Why**: removing a row moves the next one under the mouse pointer, so a fast
  second click tags the wrong transaction. It also reassigns Vimium's hints
  between clicks. Keeping the row makes a mistake visible and correctable. One
  request per row at a time keeps responses from arriving out of order.
- **Rejected**: removing rows as they are tagged, as in the previous project's
  apply step.
- **Goal**: the page does not move under the user, and mistakes cost one more
  click.

### 5. Tag choices are native buttons

- **Decision**: every tag and "Dismiss" is a native button whose accessible name
  is the tag name, or "Dismiss". Rows have no open-row overlay (the shared row
  chrome in `client/src/budgeteur/shared/`), and nothing covers the buttons.
  Only a row with a request in flight has disabled buttons.
- **Why**: Vimium's link hints reliably find native buttons and links. It finds
  elements with script click handlers, or labels over visually hidden inputs as
  in the previous project, less reliably. It skips elements another element
  covers, and the open-row overlay covers a whole row by design. Disabled
  buttons get no hint.
- **Order**: the same on every row, so positions become familiar: expense tags,
  then income tags, each by name, then "Dismiss", styled apart from the tags.
- **Rejected**: ordering tags by the amount's sign, putting income tags first
  for credits. Positions would move between rows, and refunds would put the
  likely tag second. Suggested tags belong to smart tagging.
- **Goal**: the page works from the keyboard through Vimium, with no shortcuts
  of its own.

### 6. Quick tagging is its own slice

- **Decision**: `Feature/QuickTag/` owns three endpoints, one file each:
  - `GET /api/quick-tag` returning the batch, newest first, with the total in
    the queue. Each entry has the transaction's id, date, description, amount,
    and account name.
  - `PUT /api/quick-tag/{transactionId}` with a required tag id, returning
    `204`. A tag the user does not have is `400`, whether it is missing or
    another user's.
  - `DELETE /api/quick-tag/{transactionId}` dismissing the transaction, which
    removes it from the queue, returning `204`.

  For both writes, an unknown transaction, or another user's, is `404`, and a
  transfer is `400`, checked before the write. Both are idempotent. They write
  through the shared assignment store with the quick tag transitions from
  decision 1. The page reads tags from the existing tag endpoint.
- **Why**: quick tagging is a categorisation workflow, like auto-tagging, and
  auto-tagging decision 8 placed such workflows in their own slices writing
  assignments through `Data/`. Two write operations keep the request bodies free
  of a null that means "dismiss", and the OpenAPI document cannot describe a
  union with fields ([openapi](openapi.md)).
- **Goal**: quick tagging changes for one reason, and assignments are still
  written one way.

### 7. Quick tagging is reached from where untagged transactions show

- **Decision**:
  - The transactions page header has a "Quick tag" link next to "Import".
  - The dashboard's untagged note shows the queue total, whatever the period,
    and links to quick tagging instead of the transactions page. The dashboard
    reads the total from the queue endpoint, decoding only that field, and the
    income statement drops its untagged count. The note disappears once the user
    has tagged or dismissed every transaction.
  - CSV import keeps its result toast. The import response does not gain the ids
    of the untagged transactions it created, and there is no review limited to
    one import. This replaces the review step in [CSV import](csv-import.md)
    decision 11.
  - No item in the app header: quick tagging is a transactions workflow.
- **Why**: after an import, the "Quick tag" link is next to the "Import" button
  the user just used, and newest first puts that import's leftovers at the top
  of the queue. A review limited to one import needs the ids in the response,
  client state to hold them, and a second mode of the page, and toasts have no
  links. The dashboard and the quick tagging page show the same number for the
  same work; a count per period would change with the period and differ from the
  page the note links to.
- **Rejected**:
  - The untagged count for the selected period, as the dashboard has now.
  - A count endpoint. The queue response already carries the total, and a batch
    is small. Add one if fetching the batch for its total becomes costly.
- **Goal**: going from an import or the dashboard to tagging is one click, and
  the page has one mode.

### 8. UI

- **Route**: `/quick-tagging`, a page module of its own.
- **Header**: the page title and the number of transactions still waiting: the
  queue total less the rows quick tagged in this batch.
- **Rows**: the description first, then the date, amount, and account name on
  one line, then the tag buttons, wrapping as needed. The description can be
  selected and copied. Rows do not open the transaction form; other fields are
  edited on the transactions page.
- **Empty state**: "No transactions are waiting for a tag", with a link to the
  transactions page, where the user imports and records transactions.
- **Errors**: a failed queue load shows the page's error state with a retry. A
  failed save uses the error toast (decision 4).
- **Goal**: a row reads like a bank statement line, and the tags are the only
  controls on it.

## Consequences

- **Schema**: in migration `001`, the assignment's tag becomes nullable with the
  source check from decision 1. Then `just db-reset` and `just db-update`.
- **Assignment type and transitions**: the type in `Domain/` gains the dismissed
  case and the quick tag transitions, and the transaction form, transfer, and
  auto-tagging transitions handle it as in decision 1. The codec in `Data/` maps
  the nullable tag.
- **Transaction slice**: responses give a dismissed transaction no tag. Marking
  a transfer removes its assignment.
- **Income statement**: amounts are unchanged, since untagged lines cover every
  transaction without a tag, and the tag read from the join is already optional.
  The untagged count leaves the response and its computation (decision 7).
- **Dashboard**: fetches the queue alongside the income statement and balance
  sheet, and the untagged note no longer depends on the period.
- **Docs updated with the implementation**: auto-tagging decision 4 (the
  dismissed state and its transitions) and its deferred tagging queue, CSV
  import decision 11 and its deferred quick-tagging entry, and the dashboard's
  response shape, untagged note, and deferred quick tagging entry.
- **Highest-value tests**:
  - Transitions: quick tag, dismiss, the transaction form on a dismissed
    transaction, a transfer losing its assignment, and tag untagged and re-tag
    never changing a dismissal.
  - Queue: only the caller's untagged non-transfer transactions, newest first,
    the batch size, and the total.
  - Quick tag endpoints: tag and dismiss; `404` for another user's transaction,
    `400` for a tag the user does not have and for a transfer.
  - Income statement: a dismissed transaction counts in the untagged lines.
  - Client: a click sends the request and marks the row; a row is disabled while
    saving; a failure restores the previous state and shows a toast; "Next
    batch" fetches the queue.
  - E2E: create an untagged transaction, open quick tagging from the
    transactions page, click a tag, reload; the queue is empty and the
    transactions table shows the tag. Finding the button by its role and name
    within the row checks that it is a native button, the closest a test gets to
    Vimium.

## Deferred

- **Create a rule from a transaction.** A follow-up to this feature; see
  [auto-tagging](auto-tagging.md#deferred).
- **Suggested tags.** Part of smart auto-tagging, which can rank the buttons or
  mark a suggestion without changing their order.
- **Undismiss.** A dismissed transaction returns to the queue only if it is
  tagged in the transaction form and the tag cleared, or a tag is deleted. Add
  an action if the user needs it.
- **Queue filters.** By account or period. Add if the queue grows long enough
  for newest first to be a problem.
- **Keyboard shortcuts of the page's own.** Vimium covers keyboard use.

## Assumptions

- The user has few enough tags that one row of buttons per transaction, wrapping
  onto two lines at most, stays readable.
- After rules, the queue is short enough that batches of 50 are worked through
  in a sitting.
