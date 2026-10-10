# Auto-tagging

Design brief for auto-tagging: applying the user's tagging rules to their
transactions. It records what we decided, why, and what each decision is meant
to achieve. Change it when the reasoning changes.

The previous Rust project (`budgeteur`, `server/src/rule/auto_tagging.rs`)
matched rules by case-insensitive prefix, picked the longest matching pattern,
and ran from two buttons on the rules page ("all", which overwrote every tag,
and "untagged only") and on every CSV import. It did not record whether a tag
came from a rule or the user. Lessons from it are cited where they shaped a
decision.

## Goal

- **Less manual tagging.** A rule written once tags every matching transaction,
  past and future.
- **Rules never override the user.** A tag the user chose is never changed by a
  rule.
- **Rules are predictable.** For any description and rule set, exactly one rule
  wins or none does, and the user can see what a pattern matches before saving
  it.

## Ubiquitous language

| Term         | Meaning                                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| Rule         | A pattern and the tag it applies. Rule CRUD already exists.                                                |
| Match        | A rule matches a transaction when its pattern occurs anywhere in the description, ignoring case.           |
| Comparison   | How patterns and descriptions are compared: ordinal, ignoring case. Used by matching and rule uniqueness.  |
| Winning rule | The matching rule with the longest pattern. Equal lengths are ordered by the pattern's ordinal comparison. |
| Assignment   | A transaction's tag and its source. Stored apart from the transaction; an untagged transaction has none.   |
| Tag source   | Where a transaction's tag came from: `Manual` or `Rule`.                                                   |
| Manual tag   | A tag the user set. Rules never change it.                                                                 |
| Rule tag     | A tag set by auto-tagging. Derived data: re-tagging recomputes it.                                         |
| Tag untagged | The action that applies rules to untagged transactions only.                                               |
| Re-tag       | The action that recomputes every transaction without a manual tag. Asks for confirmation first.            |
| Match count  | The number of the user's transactions a pattern matches, shown in the rule modal while editing.            |

## Decisions

### 1. Rules match by substring, ignoring case

- **Decision**: a rule matches when its pattern occurs anywhere in the
  description. Case is ignored using ordinal case-insensitive comparison, with
  no culture rules. No wildcards, regular expressions, or whitespace
  normalisation.
- **Why**: bank descriptions put the merchant after a prefix that varies by
  transaction type, e.g. Kiwibank's `PAY Alice Highbrow Food Bob` for a direct
  debit. The previous project's prefix matching could not match mid-description.
  Ordinal comparison is deterministic and independent of server culture and ICU
  version. Culture-sensitive comparison treats some characters as ignorable, so
  a pattern of only a soft hyphen would match every description.
- **Cost**: short patterns over-match. Decisions 2 and 7 mitigate this.
- **Goal**: one pattern per merchant, whatever the transaction type.

### 2. The longest matching pattern wins; patterns are unique per user

- **Decision**: when several rules match, the longest pattern wins, and equal
  lengths are ordered by ordinal comparison of the pattern. A pattern is unique
  per user, ignoring case, regardless of its tag. This replaces the current
  `UNIQUE(UserId, Pattern, TagId)`.
- **Why**: with substring matching, a longer pattern is the more specific one
  (`COUNTDOWN FUEL` over `COUNTDOWN`). The previous project also used the
  longest pattern but left ties to database row order. The current schema allows
  one pattern on two tags, a tie that has no sensible winner. The ordinal
  tie-break is arbitrary but deterministic.
- **Uniqueness check**: the pre-write check uses the same comparison as matching
  and is authoritative. The database constraint folds ASCII case only (SQLite
  `NOCASE`) and serves as the safety net, as with other constraints. The rule
  modal's duplicate check lowercases, which approximates the server's check for
  non-ASCII text, and changes from per tag to per user.
- **Rejected**: user-ordered priority. It needs a priority column and a
  reordering UI. Revisit if the longest pattern turns out to pick the wrong rule
  in practice.
- **Goal**: for a given description and rule set there is exactly one answer,
  and it does not depend on storage order.

### 3. Tag assignments are separate from transactions

- **Decision**: a transaction's tag is a tag assignment, held in its own table
  and its own domain type, keyed by transaction id. `Transactions` and the
  `Transaction` type keep the facts only: amount, description, date, account,
  transfer flag, and import hash. `Transactions.TagId` moves to the new table.
- **Why**: facts and categorisation have different lifecycles and writers. Facts
  are set on creation or import and rarely change. The tag is changed by the
  user, by rules, and later by quick-tagging and smart tagging. Keeping them in
  one row and one type would make `Transactions` grow with every tagging feature
  and make every tagging change pass through the transaction model. Separate,
  categorisation can change without touching transactions, and workflows that
  tag cannot change a transaction's facts.
- **Storage**: one row per tagged transaction, keyed by transaction id and
  holding the user id, the tag, and the tag source. Untagged means no row.
  - Transaction id references `Transactions` and tag references `Tags`, both `ON
    DELETE CASCADE`: deleting either removes the assignment.
  - Tag and source are `NOT NULL`, and the source is `Manual` or `Rule`.
  - Indexed by user id, for reading a user's assignments, and by tag id, so
    deleting a tag finds its assignments without a table scan.
  - Verified with SQLite 3.53: deleting a tag deletes its assignments and the
    constraints hold. The same constraints on columns in `Transactions` would
    fail, because a tag's `ON DELETE SET NULL` would leave a source with no tag.
- **Ownership**: the assignment type in `Domain/` owns the transitions in
  decision 4. Its row mapping is in `Data/`, because the Transaction and AutoTag
  slices both write it (decision 8).
- **Rejected**:
  - Tag columns on `Transactions`: no join, but the schema cannot enforce the
    constraints above, so the codec has to read a missing tag as untagged, and
    stale source values remain after a tag is deleted. Constraint changes to
    those columns later rebuild the largest table.
  - A separate table with the tag still on the `Transaction` type: the same
    storage, but the transaction model still changes with every tagging change.
  - Only categorisation slices write assignments, and transaction CRUD stops
    accepting a tag: saving the transaction form becomes two requests, and a
    failed second request leaves the transaction untagged. Revisit if
    categorisation needs a single writer.
- **Goal**: `Transactions` stays a stable record of what happened, and tagging
  develops independently of it.

### 4. Assignments record where the tag came from

- **Decision**: a transaction is untagged, manually tagged, or tagged by a rule.
  A rule tag does not record which rule set it.
- **Why**: re-tagging has to tell the user's decisions from derived ones. The
  previous project could not, so its "auto-tag all" overwrote manual tags. Smart
  auto-tagging (roadmap) can use manual tags as user-confirmed training labels.
- **Transitions**:
  - Creating a transaction with a tag makes it manual; without one, untagged.
  - Updating to a different tag makes it manual; clearing the tag makes it
    untagged; keeping the same tag keeps its source, so editing the amount of a
    rule-tagged transaction does not make it manual.
  - Auto-tagging sets rule tags.
  - Editing or deleting a rule leaves the rule tags it set unchanged until the
    next re-tag.
  - Deleting a tag removes its assignments, which makes those transactions
    untagged.
- **Known limitation**: clearing a tag by hand makes the transaction untagged,
  so the next run can tag it again. A "manually untagged" state would prevent
  this. Deferred until it is a problem.
- **Rejected**: a reference to the rule that set the tag, so the transactions
  table can name it. Rule edits do not change assignments (decision 5), so after
  an edit the reference names a pattern the description may not contain, or a
  rule that now applies another tag. Re-tag recomputes from the current rules
  and smart tagging uses manual tags, so nothing else needs it. Storing the
  pattern at assignment time would stay accurate; add it if the user needs to
  know which rule set a tag.
- **Goal**: re-tagging is safe to run at any time.

### 5. Auto-tagging runs when the user asks

- **Decision**: two actions. Rule create, update, and delete do not change
  assignments.
  - **Tag untagged** applies rules to untagged transactions only.
  - **Re-tag** recomputes every transaction without a manual tag: untagged ones
    get the winning rule's tag, rule tags change to the current winner, and rule
    tags with no matching rule are cleared. Manual tags never change. It asks
    for confirmation first, saying that tags set by rules may change or be
    cleared and that manual tags are kept.
- **Why**: the user decides when a rule change applies to past transactions.
  Re-tag differs from the previous project's "auto-tag all" in keeping manual
  tags; decision 4 makes that possible. Re-tag cannot be undone, and a user who
  deleted a rule to stop future tagging may not expect past tags to be cleared,
  so it is confirmed. Tag untagged only fills in missing tags, so it is not.
- **Transfers**: rules apply to internal transfers too. A tag on a transfer
  affects no statement, and a separate filter would be one more rule to explain.
- **Rejected**: live rules, where every rule change re-tags immediately. That
  removes both buttons, but every rule save rewrites assignments, and a pattern
  being typed would tag transactions part way through editing.
- **Goal**: two predictable actions, both safe to repeat.

### 6. Matching is a pure function in `Domain/`; only changes are written

- **Decision**: the matcher (which rule wins for a description) and the
  comparison it uses live with the `Rule` type in `Domain/`. A pure function
  takes the rules, the candidate transactions with their assignments, and the
  action, and returns the assignment changes. The handler loads the user's rules
  and candidates, writes the changed assignments in one database transaction,
  and returns how many transactions were tagged, changed, and cleared.
- **Why**: the matcher defines what a rule means, so it lives with the type, as
  an invariant does. The Rule slice's uniqueness check uses the comparison, and
  CSV import will be the matcher's second consumer. SQLite's `LIKE` folds ASCII
  case only and cannot express the longest-wins choice clearly. Personal data
  volumes (thousands of transactions, tens of rules) load comfortably.
- **Accepted risk**: candidates are loaded before the write transaction starts,
  so a manual tag set between the load and the write can be overwritten by a
  rule tag. Expected usage is one user on one device, which makes this unlikely.
  Loading inside the write transaction, or writing only where the assignment is
  still a rule tag or absent, would close it.
- **Goal**: one tested function owns the matching rules, and handlers only query
  and write.

### 7. The rule modal shows a match count

- **Decision**: while the pattern field is valid, the rule modal shows how many
  of the user's transactions the pattern matches and the descriptions of up to
  five of the most recent matches. It counts matches, not wins, because whether
  the rule wins depends on the other rules. Requests are debounced, and a
  response for a pattern that is no longer in the field is ignored.
- **Why**: substring patterns over-match, and seeing example matches before
  saving is the main guard against that. The previous project offered no
  feedback until after a run.
- **Goal**: the user can judge a pattern without leaving the modal.

### 8. Slices are workflows; auto-tagging is its own slice

- **Decision**: `Feature/AutoTag/` owns two endpoints:
  - `POST /api/auto-tag` with the action (`TagUntagged` or `Retag`) in the body,
    returning the counts from decision 6.
  - `GET /api/auto-tag/matches?pattern=` returning the match count and sample
    descriptions. The pattern is validated like a rule pattern (`400`).

  It writes assignments only, through the assignment type and its shared
  mapping. The Transaction slice also writes assignments, for the tag in the
  transaction form, in the same database transaction as the facts.
- **Why**: slices are grouped by workflow, and a table has one owner of its
  invariants and mapping rather than one writing slice (see
  [architecture](architecture.md#dependency-rules)). Auto-tagging reads rules
  and changes assignments, a workflow neither the Rule nor the Transaction slice
  is about.
- **Rejected**:
  - Auto-tagging in the Transaction slice, so each table has one writing slice.
    Import, auto-tagging, quick-tagging, and smart tagging would all collect
    there, and single user actions that span tables, such as CSV import or
    creating a rule from a transaction, could not be one database transaction
    without slices calling each other.
  - Auto-tagging in the Rule slice. It would write assignments from a slice
    about rule CRUD, without the clarity of a single writer.
- **Transaction responses**: carry the tag and its source. The Transaction slice
  reads assignments for this as its own read shape.
- **Goal**: each slice changes for one reason, and the rules for writing an
  assignment exist once.

### 9. UI

- **Tagging page**: the rules section has "Tag untagged" and "Re-tag all"
  buttons, disabled while a run is in progress. "Re-tag all" opens a
  confirmation modal (decision 5) and runs only when confirmed. The result is a
  toast with the counts; failures use the error toast.
- **Transactions table**: a rule tag shows a marker whose title says a rule set
  it.
- **Rule modal**: the match count and samples from decision 7, below the pattern
  field.
- **Goal**: the user can start a run and see its effect without leaving the
  page, and can tell rule tags from manual ones.

## Consequences

- **Schema**: migration `001` is unreleased (no version tag contains it), so it
  is edited in place: the `Rules` uniqueness from decision 2, the assignment
  table and its indexes from decision 3, `TagId` and its index removed from
  `Transactions`, and `TaggingQueue` and its trigger removed. Then `just
  db-reset` and `just db-update`.
- **Tagging queue**: removed. Nothing writes to it, and what it holds (which
  transactions await review, and whether rule tags count as reviewed) belongs to
  the quick-tagging design.
- **Income statement**: reads assignments to find each transaction's tag. Its
  rules do not change.
- **Transaction slice**: create and update write the facts and the assignment in
  one database transaction, as the balance sheet slice does for its item and
  statement date. Update inserts, replaces, or deletes the assignment.
- **Highest-value tests**:
  - Matcher: substring, case, longest wins, the ordinal tie-break, no match.
  - Application: `TagUntagged` leaves rule tags alone; `Retag` tags, changes,
    and clears rule tags and never touches manual tags.
  - Tag source transitions on transaction create and update.
  - Deleting a tag that has assignments (the cascade in decision 3).
  - Both endpoints read and write only the caller's data.
  - Client: each button produces its request and result toast; re-tag sends no
    request until confirmed and none when cancelled; the match count is
    debounced and ignores outdated responses.
  - E2E: create a tag, a rule, and a matching untagged transaction; "Tag
    untagged" tags it, and the table shows the rule marker.

## Deferred

- **Auto-tagging on CSV import.** Part of the CSV imports roadmap item. Imported
  transactions get rule tags in the same database transaction as their insert.
- **Tagging queue.** Part of quick-tagging. The previous project queued imported
  transactions that no rule tagged. Restore the table or replace it with a query
  over assignments when quick-tagging is designed.
- **Manually untagged state.** See the known limitation in decision 4.
- **Rule that set a tag.** See the rejected option in decision 4.
- **Preview of a re-tag.** A dry run listing what would change. Add if the
  confirmation and the counts in the result toast are not enough.
- **Create a rule from a transaction.** Belongs with quick-tagging.
- **Rules on other fields.** Amount, account, or Kiwibank's other-party fields.
  Internal transfer detection from account numbers is a separate backlog item.
- **Wildcards or regular expressions.** Substring patterns first.
- **User-ordered priority.** See decision 2.
- **Single writer for assignments.** See the rejected options in decision 3.

## Assumptions

- The description is the only field rules match on.
- One user's rules and transactions fit in memory for a run.
