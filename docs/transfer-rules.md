# Transfer rules

Design brief for transfer rules: tagging rules that propose marking matching
transactions as transfers, which the user approves in quick tagging. It records
what we decided, why, and what each decision is meant to achieve. Change it when
the reasoning changes.

It extends [auto-tagging](auto-tagging.md) and
[quick tagging](quick-tagging.md), whose decisions still hold unless this brief
replaces them. Smart tagging is the next feature, so the brief names where it
fits.

## Goal

- **Transfers without an account number.** A transfer that import cannot detect,
  such as an ASB card payment or a `TRANSFER TO SAVINGS` description, is found
  by a rule written once, not searched for by hand on every statement
  ([CSV import](csv-import.md#deferred)).
- **A rule never hides money.** A transfer is left out of the income statement
  and the quick tagging queue, so a wrong one is hard to notice. A wrong
  transfer rule leaves the transaction untagged, where the dashboard and the
  queue still show it.
- **Propose, then decide.** What produces a categorisation and whether it is
  applied without the user are separate concerns, so smart tagging adds a source
  of proposals, not a new workflow.
- **Every categorisation says who decided it**, so smart tagging can choose its
  training labels.

## Ubiquitous language

| Term             | Meaning                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------ |
| Rule target      | What a rule proposes when it wins: a tag, or a transfer.                                   |
| Tag rule         | A rule whose target is a tag. Every rule before this feature.                              |
| Transfer rule    | A rule whose target is a transfer.                                                         |
| Proposal         | A categorisation a rule or detection proposes for a transaction. Stored only once applied. |
| Policy           | Which rule proposals are applied without the user. The rest are only suggested.            |
| Source           | Who decided a categorisation: `Manual`, `Accepted`, `Rule`, or `Detected` (decision 4).    |
| Suggestion       | The proposal for a queued transaction, shown in quick tagging.                             |
| Suggestion count | How many queued transactions are suggested the same categorisation, whatever proposed it.  |
| Approve          | Applying a suggestion to every queued transaction shown.                                   |
| Accept           | Choosing a suggestion, on one row or by approving it.                                      |

Rule, match, winning rule, categorisation, tag untagged, re-tag, and match count
are defined in [auto-tagging](auto-tagging.md#ubiquitous-language); untagged,
queue, batch, and quick tag in
[quick tagging](quick-tagging.md#ubiquitous-language). This brief replaces "tag
source" with source.

## Decisions

### 1. A rule's target is a tag or a transfer

- **Decision**: a rule has a pattern and a target, which is a tag or a transfer.
  The `Rule` type in `Domain/` holds the target as a union in place of its tag
  id. A transfer rule references no tag, so deleting a tag never deletes one.
- **Why**: a transfer is a categorisation without a tag
  ([quick tagging](quick-tagging.md) decision 1), so a rule for transfers is a
  rule with a different target, not a rule with a special tag. The union keeps
  "a transfer rule with a tag" unrepresentable, as the categorisation does for
  "a tagged transfer".
- **Rejected**:
  - A reserved "Transfer" tag the income statement ignores. It brings back the
    tagged transfer that quick tagging decision 1 removed, and every reader of
    tags would special-case it, as with the rejected "No tag" tag.
  - A separate transfer rules table and slice. No `Rules` rebuild, but patterns
    would live in two places: uniqueness would span two tables, and the winner
    between a tag rule and a transfer rule matching the same description would
    need a rule of its own.
- **Goal**: one kind of rule, with one of two targets.

### 2. Transfer rules compete under the existing precedence

- **Decision**: tag rules and transfer rules form one rule set. The longest
  matching pattern wins whatever its target, with the same ordinal tie-break,
  and patterns stay unique per user whatever their target
  ([auto-tagging](auto-tagging.md) decision 2).
- **Why**: the precedence is about which pattern is more specific, and that does
  not depend on the target. A transfer rule `TRANSFER TO` and a tag rule
  `TRANSFER TO RENT` resolve the same way two tag rules would. Uniqueness
  already ignores the tag, so it needs no change to ignore the target.
- **Rejected**: transfer rules always win, or always lose. Either is a second
  ordering the user has to remember, and a short transfer pattern would then
  override a long, specific tag pattern.
- **Goal**: adding transfer rules changes nothing about how a winner is chosen.

### 3. Rules propose; a policy decides what is applied

- **Decision**: the winning rule gives a transaction's proposal, and import's
  account-number detection ([CSV import](csv-import.md) decision 9) gives one
  for the rows it identifies. Detection's transfers are always applied. A
  policy, one pure function in `Domain/`, says which rule proposals are applied
  without the user:
  - a rule's tag is applied;
  - a rule's transfer is not: it is only suggested.

  Runs and import pass the applied proposal, if any, to the existing tag
  untagged and re-tag transitions, whose results do not otherwise change
  (decision 4 changes only how re-tag recognises the user's decisions):
  - **Tag untagged** leaves an untagged transaction whose winner is a transfer
    rule untagged.
  - **Re-tag** clears a rule tag whose winner is now a transfer rule, as it
    clears a rule tag no rule wins, so the transaction returns to the queue with
    the suggestion. The result counts it as cleared.

  A shorter tag rule that also matches does not apply instead: the winner is the
  proposal, and the policy only decides whether to apply it.
- **Why**:
  - A transfer leaves the income statement and the queue at once, so a transfer
    rule that over-matches would hide money where nothing points at it. A wrong
    rule tag still shows under a tag on the dashboard. An untagged transaction
    shows in the dashboard's untagged lines and waits in the queue, so a wrong
    proposal costs a click, not a missed expense.
  - What a rule proposes and whether that kind of proposal is trusted are
    separate questions. Answering both with the target would make every new
    combination a new special case in the transitions and the types. Smart
    tagging's proposals start as suggestions only; a confidence threshold, or a
    per-rule switch between applying and suggesting, would be a change to the
    policy, not a new mechanism.
- **Rejected**:
  - Transfer rules apply transfers that re-tag recomputes, and a review page
    lists them. It keeps the automation, but a wrong transfer is hidden until
    reviewed, and the review page needs a "reviewed" fact of its own.
  - Encoding the policy in the types, with source types per kind that cannot
    express a transfer set by a rule. It makes a policy look like an invariant,
    and smart tagging or a threshold would change the types again.
  - Falling through to the longest matching tag rule when a transfer rule wins.
    The transaction would be tagged by a pattern the user wrote for something
    less specific, and the queue would never show the proposal.
- **Goal**: rules save the user finding transfers, only trusted proposals change
  categorisations without the user, and the trust in rule proposals is decided
  in one place.

### 4. Every categorisation has a source, independent of its kind

- **Decision**: a categorisation is what was decided (a tag, a dismissal, or a
  transfer) and, for a tag or a transfer, its source: `Manual`, `Accepted`,
  `Rule`, or `Detected`. A tag or a transfer can have any source in the type;
  the policy and the writers decide which combinations are written. A dismissal
  has no source in the type: it is always the user's decision, so its source is
  `Manual`.
  - The user's decisions record `Accepted` when the user chose the suggestion,
    on one row or by approval (decisions 6 and 7), and `Manual` otherwise: the
    transaction form and any other quick tag choice.
  - Applied rule tags record `Rule`; detected transfers record `Detected`.
  - Re-tag recomputes untagged transactions and those whose source is `Rule`,
    and never changes any other. The rule that "re-tag never changes a manual
    tag, a dismissal, or a transfer" becomes a rule about the source.
  - The transaction form keeps a categorisation's source when its decision is
    unchanged: keeping the same tag keeps a rule tag's source, as before, and
    saving a detected transfer with the transfer box still checked keeps it
    detected. Otherwise the form records `Manual`.
- **Why**: who decided and what was decided vary independently. Tying sources to
  kinds needs a source type per kind, a check per kind on the `Source` column,
  and a change to each type whenever a new origin of proposals appears. Which
  writer marked a transfer is known only when it is written and cannot be
  recovered afterwards; smart tagging needs it to choose its training labels,
  and re-detecting transfers during re-tag (deferred) needs to know which
  transfers detection owns. A dismissal is different: no proposal ever dismisses
  (decision 9, and dismissal rules under Deferred), so its source is an
  invariant, and the type states it.
- **Storage**: the `Source` column of `Categorisations` becomes `NOT NULL`, with
  one list of values for every kind. The checks are that a row has a tag exactly
  when it is tagged, and that a dismissal's source is `Manual`. This is the
  storage auto-tagging decision 3 first described.
- **Cost**: a rule transfer or a detected tag is representable, and the compiler
  does not stop a writer from producing one. The policy, the transitions, and
  their tests are the guard, because the restriction is a policy.
- **Rejected**:
  - A tag source and a transfer source as separate types. See decision 3.
  - No source on transfers. Nothing in this feature reads it, but the
    information is lost for every transfer written until it exists.
- **Smart tagging**: adds a `Model` source. Re-running the model recomputes the
  categorisations whose source is `Model`, as re-tag does for `Rule`, if its
  proposals are ever applied.
- **Goal**: one answer to "who decided this?", the same for every kind.

### 5. Rule tags stay stored; suggestions are computed

- **Decision**: applied proposals are written as categorisations, by runs and
  import, as auto-tagging decision 5 describes. Suggestions are computed when
  the queue is read (decision 6) and never stored.
- **Why**: the two answer different needs. A stored rule tag keeps reports
  stable until the user chooses to re-tag, and lets queries such as search's tag
  criterion filter in SQL. A suggestion only exists while the user is deciding,
  so computing it means it always reflects the current rules.
- **Rejected**: storing only the user's decisions and detected transfers, and
  computing every other categorisation on read. Besides the live rules
  auto-tagging decision 5 rejects:
  - every reader that filters by tag, such as search and its cursor paging,
    would compute categorisations in memory instead of in SQL;
  - applied smart tagging proposals would run the model on every read, and
    caching its output would bring stored derived data back.
- **Goal**: each kind of derived data is kept the way its readers need it, and
  the reason there are two is written down.

### 6. Suggestions are computed when the queue is read

- **Decision**: each queued transaction carries an optional suggestion: the
  winning rule's target and the rule's pattern, from the user's current rules.
  The QuickTag slice loads the rules with the queue and uses the matcher and the
  proposal in `Domain/`. The queue's contents and order do not change.
  - A transfer rule's suggestion is the usual case.
  - A tag rule's suggestion shows only for transactions left untagged since the
    rule was written, such as one entered by hand, or whose rule tag the user
    cleared in the transaction form. The latter is suggested the tag just
    cleared, as the next "Tag untagged" would apply it again (auto-tagging
    decision 4, known limitation); dismissing it or fixing the rule stops both.
  - Choosing the suggested button on a row, or approving the suggestion
    (decision 7), records `Accepted`. The client knows which button was the
    suggestion, so the single-row request says whether the choice was it. The
    server takes its word: the label records what the user saw, which a
    recomputed suggestion would not if a rule changed after the queue was read,
    and a wrong label affects only the user's own data.
- **Why**: a suggestion is a pure function of the rules and the description, so
  computing it on read means it cannot go stale. Editing or deleting a rule
  changes its suggestions at once, without a re-tag. After rules the queue is
  short ([quick tagging](quick-tagging.md#assumptions)) and a user has tens of
  rules, so matching the whole queue costs little. Suggesting the proposal
  whatever its target needs no special case for tag rules.
- **Rejected**: a suggestions table written by runs and import. It would need
  rewriting on every rule change, and a stale suggestion would propose a target
  no rule now gives.
- **Smart tagging**: a model's suggestion has the same shape, with the model and
  a confidence as its origin. If inference is too slow to run on read, its
  inputs, such as description embeddings, can be cached as derived data that is
  rebuilt rather than kept in sync.
- **Goal**: a suggestion always matches the current rules, and the queue needs
  no new state.

### 7. Suggestions are counted and filtered, and approved together

- **Decision**:
  - **Identity**: two suggestions are the same when they suggest the same
    categorisation, a tag or a transfer, whatever proposed them. The rule's
    pattern shows on each row, not in the identity.
  - **Counts**: the queue response carries the suggestion counts over the whole
    queue, not only the batch: each suggested categorisation and how many queued
    transactions are suggested it.
  - **Filter**: the queue takes an optional suggested categorisation and returns
    only the queued transactions suggested it, as a batch with its total, as the
    unfiltered queue does. Suggestions are computed in memory, so the filter and
    its total are too, not in SQL.
  - **Approval**: a request applies one categorisation, a tag or a transfer, to
    a list of transaction ids, and records `Accepted` for either. It applies to
    those still in the queue and skips the rest, in one database transaction,
    and returns how many it changed. Every id must belong to the user (`404`
    otherwise, checked before the write), the tag must be the user's (`400`),
    and the list holds at most a batch (`400` above). An id deleted since the
    page was read fails the whole request with `404`, as on the single-row
    endpoints, while one categorised elsewhere is skipped; the client then
    suggests refreshing the queue (decision 10). An empty list changes nothing
    and returns 0.
- **Why**: after the first import with a new rule, a suggestion may cover dozens
  of transactions, and one click per row defeats the rule. A count and a filter
  are two general pieces that the queue can use for any suggestion, from a rule
  or a model, rather than a structure for transfers only; the filter is also the
  first queue filter, which quick tagging deferred. The categorisation is the
  one identity every origin shares and keeps: a rule has an id, but the model
  proposes per transaction and has no unit like a rule, and its suggestion for a
  transaction can change when it is retrained. It is also what the filter, the
  count, and the approval all take, so one key serves the three. Sending the ids
  means the user approves exactly the rows shown. A transaction imported
  meanwhile is not swept in, and one tagged in another tab is no longer in the
  queue, so it is not overwritten. The single-row quick tag endpoints replace
  any categorisation (quick tagging decision 6) because the user is looking at
  that row and nothing else. Accepting a suggestion, on one row or many, is the
  user's decision, so re-tag leaves it as it leaves a manual one. But a choice
  made with a suggestion in view is not the same evidence as one made without,
  and `Accepted` lets smart tagging weigh the two differently, which cannot be
  recovered after the write.
- **Cost**:
  - A suggestion with more queued transactions than a batch takes one approval
    per batch.
  - A model's suggestion shares its identity with a rule's, so the smart tagging
    brief decides whether accepting the model's suggestions records `Accepted`
    or a source of its own.
  - A bulk approval and a choice on one row record the same source, though the
    user gives each row of a bulk approval less attention. Whether a suggestion
    was in view matters more to training than how many rows it covered.
  - Suggestions from different rules with the same target are counted together,
    as are a rule's and the model's for the same tag. Checking whether one rule
    over-matches means reading the patterns on the filtered rows. Few users have
    more than a handful of transfer rules.
- **Rejected**:
  - Recording `Manual`. Smart tagging could not tell a choice made with a
    suggestion in view from one made without.
  - Separate sources for a bulk approval and a choice on one row. A fifth value
    for a difference in attention that smart tagging is unlikely to use.
  - The server recomputing whether a single-row choice was the suggestion. It
    loads the rules on every write, and labels by the current rules rather than
    what the user saw.
  - Recording `Rule`. Re-tag would recompute approvals, and since the policy
    never applies a rule's transfer, it would clear every approved transfer
    unless re-tag gained a case for them.
  - Identifying a suggestion by its rule. It keeps one rule's matches apart, but
    smart tagging would need a second identity for the model's suggestions, and
    the filter would take a union of the two, which the OpenAPI document cannot
    describe.
  - Suggestion groups listed in the queue response, each with its own cap and
    order, and an approval endpoint for transfers only. A second read model, and
    smart tagging's tag suggestions would need groups too.
  - Approving by rule, resolved on the server. Shorter requests, but the
    transactions changed can differ from those the user saw.
- **Goal**: a rule's transfers from one import take one click per batch, the
  click covers only what the user saw, and suggestions from any origin are
  counted, filtered, and approved by the same key.

### 8. Import applies detection, then rules, through the policy

- **Decision**: in step 4 of [CSV import](csv-import.md) decision 8, a row
  detection identifies is a detected transfer. Every other row gets the winning
  rule's proposal through the policy and the tag untagged transition, so it gets
  a rule tag or stays untagged. The import's counts do not change: a row a
  transfer rule wins is neither a transfer nor tagged by a rule.
- **Why**: an account number is stronger evidence than a description, so
  detection comes first, and its proposals are applied. The queue, which the
  transactions page and dashboard already link to, shows what is left to decide,
  so the import result does not count it.
- **Rejected**: a "suggested as transfers" count in the import and run results.
  It reports the queue's state rather than what the import or run did, and each
  new origin of suggestions would add another count.
- **Goal**: an import and a later "Tag untagged" leave the same rows untagged.

### 9. API

- **Decision**:
  - **Rules**: create and update take a target (`Tag` or `Transfer`) and a tag
    id. The tag id is required for a tag rule and rejected for a transfer rule,
    both `400`, as the transaction request rejects a transfer with a tag. The
    rule response carries the target and an optional tag id.
  - **Queue**: `GET /api/quick-tag` takes an optional target and tag id to
    filter by, validated as for rules, and returns each row's optional
    suggestion (target, tag id for a tag, and the rule's pattern) and the
    suggestion counts (target, tag id for a tag, and count). Counts are ordered
    as the row buttons are, expense tags then income tags, each by name, then
    transfer ([quick tagging](quick-tagging.md) decision 5), so the count
    buttons do not move between reads and match the rows below them.
  - **Approval**: `POST /api/quick-tag/approvals` with a target, an optional tag
    id validated as for rules, and the transaction ids, returning how many it
    changed.
  - **Quick tag and transfer**: the single-row tag and transfer requests gain a
    required flag saying whether the choice was the row's suggestion; the
    transfer request, which had no body, gains one. Dismissing is never a
    suggestion, so its request is unchanged.
  - **Auto-tag runs and import**: unchanged.
  - **Transactions**: a transaction response's tag still carries its source,
    whose values gain `Accepted` and `Detected`. The client accepts every value
    and treats only `Rule` as a rule tag. The response does not carry a
    transfer's source; nothing in the client reads it yet.
- **Why**: the OpenAPI document cannot describe a union with fields
  ([openapi](openapi.md)), so a target is an enum with an optional tag id and
  the server validates the pair. A null tag id that means "transfer" was
  rejected for quick tagging's endpoints for the same reason. Rules, the queue
  filter, the suggestion counts, and approval share the pair. Approval is its
  own operation because it takes a list and reports a count, unlike the
  single-row endpoints.
- **Goal**: each request and response describes a rule, a suggestion, or an
  approval with no value that contradicts another.

### 10. UI

- **Tagging page**: the tag list ends with a "Transfers" entry, styled apart
  from the tags as quick tagging styles its "Transfer" button. Selecting it
  shows the transfer rules in the rules panel, with its own empty state and a
  note that transfer rules suggest in quick tagging rather than apply. "+ New
  Rule" there opens the rule modal with the transfer target chosen. The page's
  selection becomes a tag or the transfers entry. The empty state without tags
  is unchanged.
- **Rule modal**: the tag select ends with a "Transfer" option. The duplicate
  check, hint, match count, and samples are unchanged: a transfer rule's matches
  leave the count once the user approves them.
- **Rule delete modal**: for a transfer rule, says matching transactions will no
  longer be suggested as transfers, rather than no longer auto-tagged.
- **Quick tagging rows**: the suggested button is marked, with a visible
  "Suggested" label and the rule's pattern beside it, without moving it, so the
  order and Vimium's link hints stay the same
  ([quick tagging](quick-tagging.md#deferred)). The button's accessible name is
  unchanged.
- **Quick tagging suggestions**: above the rows, one button per suggestion count
  with the suggested tag or "Transfer" and the count. Choosing one filters the
  queue to it and shows an approval button for the rows shown, such as "Mark 14
  as transfers"; each row still shows the pattern that suggested it, so the user
  checks the patterns before approving. The approval button sends and counts
  only the rows not yet decided on the page. A control clears the filter. After
  an approval the page fetches the queue again, keeps the filter until its count
  reaches zero, and a toast reports the count. When an approval fails with `404`
  because a row was deleted elsewhere, the error toast asks the user to refresh
  the queue.
- **Goal**: transfer rules are written where tag rules are, and approved where
  untagged transactions are already handled.

### 11. Migration 002 rebuilds `Rules` and `Categorisations`

- **Decision**: migration `001` is released (1.0.0-rc1 to rc3 contain it), so
  migration `002` makes the changes. SQLite cannot change a column's nullability
  or a table's checks in place, so `002` rebuilds both tables: create the new
  table, copy the rows, drop the old one, rename, and recreate its indexes.
  - `Rules` gains a required target, and its tag id becomes nullable, with a
    check that a rule has a tag id exactly when it is a tag rule. Existing rules
    become tag rules. The per-user pattern uniqueness is unchanged.
  - `Categorisations` gets the required source from decision 4. Existing
    transfers and dismissals get `Manual`: whether a transfer was detected was
    not recorded.
  - The migration runner applies each script in its own database transaction, so
    a rebuild that fails partway leaves both tables as they were. It currently
    applies scripts without one, and `002` is the first migration that drops a
    table.
- **Why**: no table references either of them, so dropping them cascades
  nowhere, and foreign keys can stay enforced during the rebuild. Copying
  preserves every row, so existing data keeps its behaviour. A transaction per
  script in the runner, rather than in the script, covers every later migration
  too; SQLite's schema changes are transactional, so no migration needs to opt
  out.
- **Cost**: transfers detected before `002` are labelled `Manual`. Smart tagging
  sees them as user decisions, which for account-number matches is close to
  true.
- **Goal**: an upgraded database behaves exactly as before until the user writes
  a transfer rule.

## Consequences

- **Domain**: the rule target in `Domain/Rule`; the source and the transitions
  in `Domain/Categorisation`, with re-tag deciding by source; the proposal and
  the policy beside them. The matcher is unchanged.
- **Data**: the categorisation codec maps one source for tags and transfers, and
  `Manual` for a dismissal; the rule codec maps the target; `Db.fs` is
  regenerated after `002`. The server's migration runner applies each script in
  a transaction.
- **Rule slice**: request validation and response shape from decision 9.
- **AutoTag slice**: runs apply proposals through the policy. Its counts and the
  match count are unchanged.
- **Import slice**: detection records `Detected`; rules go through the policy.
- **QuickTag slice**: the queue loads rules and adds suggestions, counts, and
  the filter; the approval endpoint; writes record `Accepted` for an approval or
  a suggested choice, and `Manual` otherwise.
- **Transaction slice**: the form's transitions keep the source of an unchanged
  decision and otherwise record `Manual`. The response's tag source gains
  `Accepted` and `Detected`.
- **Income statement, dashboard, reports**: leave out transfers by kind, so they
  are unchanged.
- **Client**: the rule type gains its target; the transaction tag source decoder
  accepts the new values; the tagging page selection and the rule modal option;
  the quick tagging suggestion marker, counts, filter, and approval.
- **Smart tagging**: adds an origin of proposals (the model, with a confidence),
  a `Model` source, and a line of the policy, initially "suggest only". It
  trains on `Manual` and `Accepted` categorisations, weighted as its brief
  decides, optionally `Detected` transfers, and leaves out `Rule` and `Model`
  ones. Its suggestions use the queue's suggestion, counts, filter, and approval
  unchanged, with the model's confidence on each row in place of a pattern. Its
  brief decides which suggestion a transaction gets when a rule and the model
  both propose one (the rule, which the user wrote, is the likely answer),
  whether counts are split by confidence, and which source accepting the model's
  suggestions records.
- **Docs updated with the implementation**:
  - [auto-tagging](auto-tagging.md): the rule and categorisation terms and tag
    source; decisions 3 and 4 (one source for every kind, re-tag by source), 5
    (a transfer rule winner clears a rule tag and leaves untagged ones
    untagged); the deferred rules on other fields.
  - [quick tagging](quick-tagging.md): decision 1 (dismissals and transfers have
    a source), decisions 2 and 6 (suggestions, counts, the filter, and the
    approval endpoint, and the single-row suggestion flag), decision 8 (rows and
    suggestions), and the deferred suggested tags and queue filters, which this
    feature starts.
  - [CSV import](csv-import.md): decisions 8 and 9, and the deferred transfers
    without another party column, which transfer rules now suggest.
  - [database](database.md): each migration script runs in a transaction.
- **Highest-value tests**:
  - Policy: a rule's tag is applied; a rule's transfer is not.
  - Transitions: tag untagged and re-tag never produce a transfer with the
    `Rule` source; tag untagged leaves a transfer rule winner untagged; re-tag
    clears a rule tag whose winner is now a transfer rule and changes nothing
    whose source is not `Rule`, approvals included; a transfer rule beats a
    shorter tag rule that also matches; the transaction form keeps a detected
    transfer's source.
  - Precedence: a longer tag pattern beats a shorter transfer pattern, and the
    reverse.
  - Suggestions: the winning target and pattern for each row, none when no rule
    matches, and editing a rule changes the suggestion without a run.
  - Counts and filter: counted over the whole queue by suggested categorisation,
    with two transfer rules' suggestions counted together; the filter returns
    only rows suggested that categorisation, with their total.
  - Quick tag and transfer: a choice flagged as the suggestion records
    `Accepted`, otherwise `Manual`.
  - Approval: changes only listed transactions still in the queue, recording
    `Accepted`; skips tagged ones; `404` for another user's id with nothing
    written; `400` for another user's tag and for more than a batch of ids.
  - Rule endpoints: a tag rule without a tag id and a transfer rule with one are
    `400`; deleting a tag leaves transfer rules; data is scoped to the caller.
  - Import: a detected row records `Detected`; a row a transfer rule wins stays
    untagged.
  - Migration: applied to a database copied from an rc3 install, existing rules
    become tag rules, and existing transfers and dismissals become manual.
  - Client: selecting "Transfers" shows transfer rules; the rule modal sends the
    transfer target without a tag id; the suggested button is marked without
    moving, and choosing it sends the suggestion flag; choosing a suggestion
    count filters the queue; the approval button sends the shown ids and fetches
    the queue again; a failed approval shows the error toast and keeps the
    filter; a transaction whose tag source is `Accepted` decodes and is not
    treated as a rule tag.
  - E2E: create a transfer rule and two matching untagged transactions; "Tag
    untagged" leaves them untagged; quick tagging marks the suggestion and
    counts both; filtering and "Mark 2 as transfers" empties the queue, and the
    transactions table shows both as transfers.

## Deferred

- **Applying more proposals without the user.** A per-rule switch between
  applying and suggesting, a smart tagging confidence threshold, or a transfer
  rule match with a counterpart on another account. Each is a change to the
  policy; decide when precision is known.
- **Transfers on the dashboard.** A transfers in and out line beside the income
  statement, so marked transfers have a visible total. Less needed while only
  the user and detection mark transfers.
- **Searching by source.** A transaction search option for detected or manual
  transfers, or rule tags. Add when a user needs to audit them.
- **Re-detecting transfers during re-tag.** Run import's account-number
  detection over existing transactions. Needs the other party's account stored
  on transactions, which import does not do today. Storing it early would also
  give smart tagging a feature that cannot be recovered from old rows.
- **Rules on other fields.** Account, amount sign, or other party. See
  [auto-tagging](auto-tagging.md#deferred).
- **Transfer rules without tags.** The tagging page's empty state hides the rule
  panels until the user has a tag. Revisit if a user starts with transfer rules.
- **Dismissal rules.** Not planned: a dismissal is the user's decision that a
  transaction has no tag, so the policy never applies one from a rule.

## Assumptions

- Transfers the user cannot detect by account number have recognisable
  descriptions.
- Few transfers were dismissed before transfer rules existed. A dismissed
  transaction is not in the queue, so no rule suggests it, and it still counts
  as untagged income or expense.
- One user's rules and queued transactions fit in memory when the queue is read,
  as they do for a run. Counting suggestions loads every queued description on
  each read, not only the batch, so the queue is largest after a first import of
  several years of history before any rules exist; that is still thousands of
  rows, not millions.
